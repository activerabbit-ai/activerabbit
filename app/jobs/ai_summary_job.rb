class AiSummaryJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 2

  def perform(issue_id, event_id, project_id)
    project = ActsAsTenant.without_tenant { Project.find(project_id) }
    ActsAsTenant.current_tenant = project.account

    issue = Issue.find(issue_id)
    event = Event.find(event_id)
    account = issue.account

    # Double-check: skip if summary was already generated (race condition guard)
    return if issue.ai_summary.present?

    # Check quota
    if account && !account.within_quota?(:ai_summaries)
      Rails.logger.warn("[Quota] AI summary skipped for issue #{issue.id} - account #{account.id} over quota")
      return
    end

    # Team/Business plans require an active subscription for AI summaries
    if account
      plan_key = account.send(:effective_plan_key) rescue :free
      if %i[team business].include?(plan_key) && !account.active_subscription?
        Rails.logger.warn("[Quota] AI summary skipped for issue #{issue.id} - account #{account.id} on #{plan_key} without active subscription")
        return
      end
    end

    github_client = build_github_client(project)
    ai = AiSummaryService.new(account: account, issue: issue, sample_event: event, github_client: github_client).call
    if ai[:summary].present?
      issue.update(ai_summary: ai[:summary], ai_summary_generated_at: Time.current)

      # Trigger auto-fix pipeline (on by default when GitHub connected)
      if project.auto_fix_enabled?
        severity_ok = Issue::SEVERITIES.index(issue.calculated_severity).to_i >=
                      Issue::SEVERITIES.index(project.auto_fix_min_severity).to_i
        if severity_ok
          AutoFixJob.perform_async(issue.id, project.id)
        else
          Rails.logger.info "[AiSummaryJob] Auto-fix skipped for issue ##{issue.id}: severity #{issue.calculated_severity} < #{project.auto_fix_min_severity}"
        end
      end
    end

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "[AiSummaryJob] Record not found: #{e.message}"
    # Don't retry - the record is gone
  rescue => e
    Rails.logger.error "[AiSummaryJob] Error generating AI summary for issue #{issue_id}: #{e.message}"
    raise e
  end

  private

  def build_github_client(project)
    return nil unless project&.github_repo_full_name.present?

    settings = project.settings || {}
    installation_id = settings["github_installation_id"]
    project_pat = settings["github_pat"]
    env_pat = ENV["GITHUB_TOKEN"]

    token_manager = Github::TokenManager.new(
      project_pat: project_pat,
      installation_id: installation_id,
      env_pat: env_pat,
      project_app_id: settings["github_app_id"],
      project_app_pk: settings["github_app_pk"],
      env_app_id: ENV["AR_GH_APP_ID"],
      env_app_pk: Github::TokenManager.resolve_env_private_key
    )

    token = token_manager.get_token
    return nil unless token.present?

    Github::ApiClient.new(token)
  rescue => e
    Rails.logger.warn "[AiSummaryJob] Could not create GitHub client: #{e.message}"
    nil
  end
end
