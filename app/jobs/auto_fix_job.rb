# frozen_string_literal: true

class AutoFixJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 1

  # Automatically creates a GitHub PR with an AI-generated fix for an issue.
  # Triggered after AiSummaryJob generates a summary with a suggested fix.
  #
  # Pipeline: Error → Ingest → AI Summary → AutoFixJob → PR created
  #         → AutoFixMonitorJob polls CI → auto-merge (if configured)
  def perform(issue_id, project_id)
    project = ActsAsTenant.without_tenant { Project.find(project_id) }
    ActsAsTenant.current_tenant = project.account

    issue = Issue.find(issue_id)

    unless eligible?(issue, project)
      Rails.logger.info "[AutoFix] Skipped issue ##{issue.id}: not eligible"
      return
    end

    case gate_check(issue, project)
    when :skipped_no_github
      issue.update_columns(auto_fix_status: "skipped_no_github")
      return
    when :skipped_low_confidence
      issue.update_columns(auto_fix_status: "skipped_low_confidence")
      return
    when :skipped_capped
      issue.update_columns(auto_fix_status: "skipped_capped")
      return
    when :off
      return
    end

    # Prevent duplicate PRs (idempotency)
    dedup_key = "auto_fix:#{issue.id}"
    locked = Sidekiq.redis { |c| c.set(dedup_key, "1", nx: true, ex: 1.hour.to_i) }
    unless locked
      Rails.logger.info "[AutoFix] Skipped issue ##{issue.id}: already in progress"
      return
    end

    issue.update_columns(
      auto_fix_status: "creating_pr",
      auto_fix_attempted_at: Time.current,
      auto_fix_error: nil
    )

    pr_service = Github::PrService.new(project)
    result = pr_service.create_pr_for_issue(issue)

    if result[:success]
      pr_number = extract_pr_number(result[:pr_url])

      issue.update_columns(
        auto_fix_status: result[:actual_fix_applied] ? "pr_created" : "pr_created_review_needed",
        auto_fix_pr_url: result[:pr_url],
        auto_fix_pr_number: pr_number,
        auto_fix_branch: result[:branch_name]
      )

      persist_pr_url(project, issue, result[:pr_url])
      track_ai_request(project.account, "auto_fix_pr")

      Rails.logger.info "[AutoFix] PR created for issue ##{issue.id}: #{result[:pr_url]} (fix_applied=#{result[:actual_fix_applied]})"

      if project.auto_merge_enabled?
        schedule_monitor(issue, project)
      end
    else
      issue.update_columns(
        auto_fix_status: "failed",
        auto_fix_error: result[:error]
      )
      Rails.logger.error "[AutoFix] PR creation failed for issue ##{issue.id}: #{result[:error]}"
    end

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "[AutoFix] Record not found: #{e.message}"
  rescue => e
    Rails.logger.error "[AutoFix] Error for issue #{issue_id}: #{e.message}"
    begin
      issue = ActsAsTenant.without_tenant { Issue.find_by(id: issue_id) }
      issue&.update_columns(auto_fix_status: "failed", auto_fix_error: e.message)
    rescue
      nil
    end
    raise e
  end

  private

  def eligible?(issue, project)
    return false unless project.auto_fix_enabled?
    return false unless issue.ai_summary.present?
    return false unless issue.auto_fix_status.nil?
    return false unless issue.status == "open"
    return false if issue.count > 1 && !issue.auto_fix_status.nil?
    true
  end

  def extract_pr_number(pr_url)
    match = pr_url.to_s.match(%r{/pull/(\d+)})
    match[1].to_i if match
  end

  def persist_pr_url(project, issue, pr_url)
    settings = project.settings || {}
    issue_pr_urls = settings["issue_pr_urls"] || {}
    issue_pr_urls[issue.id.to_s] = pr_url
    settings["issue_pr_urls"] = issue_pr_urls
    project.update_column(:settings, settings)
  end

  def track_ai_request(account, request_type)
    AiRequest.create!(
      account: account,
      request_type: request_type,
      occurred_at: Time.current
    )
  rescue => e
    Rails.logger.warn "[AutoFix] Failed to track AI request: #{e.message}"
  end

  def schedule_monitor(issue, project)
    # Wait 2 minutes for CI to start, then begin monitoring
    AutoFixMonitorJob.perform_in(2.minutes, issue.id, project.id)
  end

  def gate_check(issue, project)
    return :skipped_no_github     if project.settings.to_h["github_installation_id"].blank?
    return :off                   if project.auto_pr_confidence_threshold.to_i.zero?
    return :skipped_low_confidence if issue.sre_confidence.to_i < project.auto_pr_confidence_threshold.to_i
    return :skipped_capped        if cap_reached?(project)
    :pass
  end

  def cap_reached?(project)
    used = project.issues
                  .where.not(auto_fix_status: nil)
                  .where("auto_fix_attempted_at > ?", 7.days.ago)
                  .count
    used >= project.auto_pr_weekly_cap.to_i
  end
end
