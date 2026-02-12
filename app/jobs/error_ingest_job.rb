class ErrorIngestJob
  include Sidekiq::Job

  sidekiq_options queue: :ingest, retry: 3

  def perform(project_id, payload, batch_id = nil)
    # Find project without tenant scoping, then set the tenant
    project = ActsAsTenant.without_tenant { Project.find(project_id) }
    ActsAsTenant.current_tenant = project.account

    # Convert string keys to symbols if needed
    payload = payload.is_a?(Hash) ? payload.deep_symbolize_keys : payload

    # Ingest the error event
    event = Event.ingest_error(project: project, payload: payload)

    # Track SQL queries if provided
    if payload[:sql_queries].present?
      payload[:sql_queries].each do |query_data|
        SqlFingerprint.track_query(
          project: project,
          sql: query_data[:sql] || query_data["sql"],
          duration_ms: query_data[:duration_ms] || query_data["duration_ms"] || 0,
          controller_action: payload[:controller_action]
        )
      end

      # Detect N+1 queries
      n_plus_one_incidents = SqlFingerprint.detect_n_plus_one(
        project: project,
        controller_action: payload[:controller_action],
        sql_queries: payload[:sql_queries]
      )

      # Queue alerts for significant N+1 issues
      if n_plus_one_incidents.any? { |incident| incident[:severity] == "high" }
        NPlusOneAlertJob.perform_async(project.id, n_plus_one_incidents)
      end
    end

    # Debounce project last_event_at updates (at most once per minute per project)
    cache_key = "project_last_event:#{project.id}"
    unless Rails.cache.read(cache_key)
      project.update_column(:last_event_at, Time.current)
      Rails.cache.write(cache_key, true, expires_in: 1.minute)
    end

    # Check if this error should trigger an alert
    issue = event.issue

    if issue && should_alert_for_issue?(issue)
      IssueAlertJob.perform_async(issue.id, issue.project.account_id)
    end

    # Auto-generate AI summary for NEW unique issues within quota
    if issue && issue.count == 1 && issue.ai_summary.blank?
      account = project.account
      if account&.eligible_for_auto_ai_summary?
        AiSummaryJob.perform_async(issue.id, event.id, project.id)
      end
    end

    Rails.logger.info "Processed error event for project #{project.slug}: #{event.id}"

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Project not found for error ingest: #{project_id}"
    raise e
  rescue => e
    Rails.logger.error "Error processing error ingest: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end

  private

  def should_alert_for_issue?(issue)
    return false unless issue.status == "open"

    # Alert conditions:
    # 1. New issue (first occurrence)
    # 2. Issue that was resolved but is now happening again
    # 3. Issue with high frequency (>10 occurrences in last hour)

    return true if issue.count == 1 # New issue

    # Check if issue was recently closed and is now recurring
    if issue.closed_at && issue.closed_at > 1.day.ago
      return true
    end

    # Check frequency in last hour
    recent_events = issue.events.where("created_at > ?", 1.hour.ago).count
    return true if recent_events >= 10

    false
  end

end
