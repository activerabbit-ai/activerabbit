class ErrorIngestJob
  include Sidekiq::Job

  sidekiq_options queue: :ingest, retry: 1

  # TTL for idempotency keys (10 minutes). Covers Sidekiq retries, inline
  # fallback double-fires, and deploy-related duplicate enqueues.
  DEDUP_TTL = 600

  def perform(project_id, payload, batch_id = nil)
    # Convert string keys to symbols if needed
    payload = payload.is_a?(Hash) ? payload.deep_symbolize_keys : payload

    # Idempotency: prevent duplicate processing when Sidekiq executes the
    # same job twice (retry after partial success, inline fallback + async,
    # or Redis reconnect during deploy).
    dedup_key = build_dedup_key(project_id, payload)
    if dedup_key
      already_processed = Sidekiq.redis { |c| c.set(dedup_key, "1", nx: true, ex: DEDUP_TTL) }
      unless already_processed
        Rails.logger.info "[ErrorIngestJob] Duplicate skipped: #{dedup_key}"
        return
      end
    end

    # Find project without tenant scoping, then set the tenant
    project = ActsAsTenant.without_tenant { Project.find(project_id) }
    ActsAsTenant.current_tenant = project.account

    # Hard cap: free plan stops accepting events once quota is reached.
    # This is a safety net — the API controller also checks, but jobs may
    # already be enqueued before the cap was reached.
    account = project.account
    if account&.free_plan_events_capped?
      Rails.logger.info "[ErrorIngestJob] Dropped: free plan cap reached for account #{account.id}"
      return
    end

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

    # Auto-generate AI summary for NEW unique issues within quota.
    # Uses Redis atomic counter to prevent over-enqueuing when many ingest
    # jobs run in parallel (cached_ai_summaries_used is only updated hourly).
    if issue && issue.count == 1 && issue.ai_summary.blank?
      account = project.account
      if account&.eligible_for_auto_ai_summary?
        redis_key = "ai_summary_enqueued:#{account.id}:#{Date.current.strftime('%Y-%m')}"
        count = Sidekiq.redis { |c| c.incr(redis_key) }
        # Set TTL on first increment (expires after 35 days to cover billing period)
        Sidekiq.redis { |c| c.expire(redis_key, 35.days.to_i) } if count == 1

        if count <= account.ai_summaries_quota
          AiSummaryJob.perform_async(issue.id, event.id, project.id)
        else
          Rails.logger.info("[Quota] AI auto-summary skipped for issue #{issue.id} — Redis counter #{count} >= quota #{account.ai_summaries_quota}")
        end
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

  def build_dedup_key(project_id, payload)
    # Prefer request_id (unique per HTTP request from Rails middleware)
    request_id = payload[:request_id] || payload["request_id"]
    if request_id.present?
      return "ingest_dedup:#{project_id}:#{request_id}"
    end

    # Fallback: deterministic hash of payload content.
    # Requires occurred_at to be present — without it we can't reliably
    # distinguish separate events (e.g. two genuinely different errors with
    # the same class/message). In production the client gem always sends
    # occurred_at; on Sidekiq double-fire the duplicate has the same value.
    occurred_at = payload[:occurred_at] || payload["occurred_at"]
    return nil if occurred_at.blank?

    key_data = [
      project_id,
      payload[:exception_class] || payload["exception_class"],
      payload[:message] || payload["message"],
      occurred_at,
      payload[:controller_action] || payload["controller_action"]
    ].compact.join("|")
    "ingest_dedup:#{project_id}:#{Digest::SHA256.hexdigest(key_data)[0..15]}"
  end

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
