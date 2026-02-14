# Processes a batch of performance payloads in a SINGLE Sidekiq job.
# Replaces N individual PerformanceIngestJob calls with 1 job per batch.
class PerformanceBatchIngestJob
  include Sidekiq::Job

  sidekiq_options queue: :ingest, retry: 1

  def perform(project_id, payloads, batch_id = nil)
    project = ActsAsTenant.without_tenant { Project.find(project_id) }

    # Hard cap: free plan stops accepting events once quota is reached
    if project.account&.free_plan_events_capped?
      Rails.logger.info "[PerfBatchIngest] Dropped batch: free plan cap reached for account #{project.account.id}"
      return
    end

    ActsAsTenant.with_tenant(project.account) do
      payloads.each do |payload|
        process_single_performance(project, payload)
      rescue => e
        Rails.logger.error "[PerfBatchIngest] Failed event in batch #{batch_id}: #{e.class}: #{e.message}"
      end

      # Debounce project last_event_at
      cache_key = "project_last_perf_event:#{project.id}"
      unless Rails.cache.read(cache_key)
        project.update_column(:last_event_at, Time.current)
        Rails.cache.write(cache_key, true, expires_in: 1.minute)
      end
    end

  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "[PerfBatchIngest] Project not found: #{project_id}"
  end

  private

  def process_single_performance(project, payload)
    payload = payload.deep_symbolize_keys if payload.respond_to?(:deep_symbolize_keys)

    # Track SQL queries
    if payload[:sql_queries].present?
      n_plus_one_incidents = SqlFingerprint.detect_n_plus_one(
        project: project,
        controller_action: payload[:controller_action],
        sql_queries: payload[:sql_queries]
      )

      payload[:n_plus_one_detected] = n_plus_one_incidents.any?
      payload[:context] ||= {}
      payload[:context][:n_plus_one_detected] = payload[:n_plus_one_detected]

      payload[:sql_queries].each do |query_data|
        SqlFingerprint.track_query(
          project: project,
          sql: query_data[:sql] || query_data["sql"],
          duration_ms: query_data[:duration_ms] || query_data["duration_ms"] || 0,
          controller_action: payload[:controller_action]
        )
      end
    end

    event = PerformanceEvent.ingest_performance(project: project, payload: payload)

    if should_alert_for_performance?(event)
      PerformanceAlertJob.perform_async(event.id)
    end
  end

  def should_alert_for_performance?(event)
    return false unless event.duration_ms
    return true if event.duration_ms > 5000

    ctx = event.context || {}
    return true if ctx.is_a?(Hash) && (ctx["n_plus_one_detected"] || ctx[:n_plus_one_detected])

    recent_avg = calculate_recent_average_duration(event)
    return true if recent_avg && event.duration_ms > recent_avg * 3

    false
  end

  def calculate_recent_average_duration(event)
    return nil unless event.target.present?

    recent_events = PerformanceEvent
                      .where(project: event.project)
                      .where(target: event.target)
                      .where("occurred_at > ?", 1.hour.ago)
                      .where.not(duration_ms: nil)
                      .limit(100)

    return nil if recent_events.count < 5
    recent_events.average(:duration_ms)
  end
end
