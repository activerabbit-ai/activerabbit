# Processes a batch of error payloads in a SINGLE Sidekiq job.
# This replaces the old pattern of 1 job per event (N jobs per batch API request),
# reducing queue pressure by ~50x under high traffic.
class ErrorBatchIngestJob
  include Sidekiq::Job

  sidekiq_options queue: :ingest, retry: 1

  # TTL for idempotency keys (10 minutes)
  DEDUP_TTL = 600

  def perform(project_id, payloads, batch_id = nil)
    # Batch-level idempotency: if Sidekiq retries the entire batch job,
    # skip it if the batch was already processed.
    if batch_id.present?
      dedup_key = "batch_ingest_dedup:#{project_id}:#{batch_id}"
      already_processed = Sidekiq.redis { |c| c.set(dedup_key, "1", nx: true, ex: DEDUP_TTL) }
      unless already_processed
        Rails.logger.info "[ErrorBatchIngest] Duplicate batch skipped: #{batch_id}"
        return
      end
    end

    project = ActsAsTenant.without_tenant { Project.find(project_id) }
    ActsAsTenant.current_tenant = project.account

    payloads.each do |payload|
      process_single_error(project, payload, batch_id)
    rescue => e
      # Log and continue — don't let one bad event kill the whole batch
      Rails.logger.error "[ErrorBatchIngest] Failed event in batch #{batch_id}: #{e.class}: #{e.message}"
    end

    # Debounce project last_event_at (at most once per minute per project)
    cache_key = "project_last_event:#{project.id}"
    unless Rails.cache.read(cache_key)
      project.update_column(:last_event_at, Time.current)
      Rails.cache.write(cache_key, true, expires_in: 1.minute)
    end

  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "[ErrorBatchIngest] Project not found: #{project_id}"
    # Don't re-raise — project is gone, retrying won't help
  end

  private

  def process_single_error(project, payload, batch_id)
    payload = payload.deep_symbolize_keys if payload.respond_to?(:deep_symbolize_keys)

    event = Event.ingest_error(project: project, payload: payload)
    return unless event

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

      n_plus_one_incidents = SqlFingerprint.detect_n_plus_one(
        project: project,
        controller_action: payload[:controller_action],
        sql_queries: payload[:sql_queries]
      )

      if n_plus_one_incidents.any? { |incident| incident[:severity] == "high" }
        NPlusOneAlertJob.perform_async(project.id, n_plus_one_incidents)
      end
    end

    issue = event.issue

    if issue && should_alert_for_issue?(issue)
      IssueAlertJob.perform_async(issue.id, issue.project.account_id)
    end

    # Auto-generate AI summary for NEW unique issues within quota
    if issue && issue.count == 1 && issue.ai_summary.blank?
      account = project.account
      if account&.eligible_for_auto_ai_summary?
        redis_key = "ai_summary_enqueued:#{account.id}:#{Date.current.strftime('%Y-%m')}"
        count = Sidekiq.redis { |c| c.incr(redis_key) }
        Sidekiq.redis { |c| c.expire(redis_key, 35.days.to_i) } if count == 1

        if count <= account.ai_summaries_quota
          AiSummaryJob.perform_async(issue.id, event.id, project.id)
        end
      end
    end
  end

  def should_alert_for_issue?(issue)
    return false unless issue.status == "open"
    return true if issue.count == 1
    return true if issue.closed_at && issue.closed_at > 1.day.ago

    recent_events = issue.events.where("created_at > ?", 1.hour.ago).count
    recent_events >= 10
  end
end
