class PerformanceIngestJob
  include Sidekiq::Job

  sidekiq_options queue: :ingest, retry: 3

  def perform(project_id, payload, batch_id = nil)
    project = Project.find(project_id)

    # Convert string keys to symbols if needed
    payload = payload.deep_symbolize_keys if payload.respond_to?(:deep_symbolize_keys)

    # Detect N+1 queries if SQL queries are provided
    if payload[:sql_queries].present?
      n_plus_one_incidents = SqlFingerprint.detect_n_plus_one(
        project: project,
        controller_action: payload[:controller_action],
        sql_queries: payload[:sql_queries]
      )

      payload[:n_plus_one_detected] = n_plus_one_incidents.any?

      # Track individual SQL queries
      payload[:sql_queries].each do |query_data|
        SqlFingerprint.track_query(
          project: project,
          sql: query_data[:sql] || query_data['sql'],
          duration_ms: query_data[:duration_ms] || query_data['duration_ms'] || 0,
          controller_action: payload[:controller_action]
        )
      end
    end

    # Ingest the performance event
    event = Event.ingest_performance(project: project, payload: payload)

    # Update project last event timestamp
    project.update!(last_event_at: Time.current)

    # Check for performance alerts
    if should_alert_for_performance?(event)
      PerformanceAlertJob.perform_async(event.id)
    end

    Rails.logger.info "Processed performance event for project #{project.slug}: #{event.id}"

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Project not found for performance ingest: #{project_id}"
    raise e
  rescue => e
    Rails.logger.error "Error processing performance ingest: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end

  private

  def should_alert_for_performance?(event)
    return false unless event.duration_ms

    # Alert conditions:
    # 1. Very slow request (>5 seconds)
    # 2. N+1 query detected
    # 3. Unusual spike in response time compared to recent average

    return true if event.duration_ms > 5000 # 5 seconds
    return true if event.n_plus_one_detected?

    # Check for performance spike
    recent_avg = calculate_recent_average_duration(event)
    if recent_avg && event.duration_ms > recent_avg * 3 # 3x slower than average
      return true
    end

    false
  end

  def calculate_recent_average_duration(event)
    return nil unless event.controller_action

    # Get average duration for this controller action in the last hour
    recent_events = Event.performance
                         .where(project: event.project)
                         .where(controller_action: event.controller_action)
                         .where('occurred_at > ?', 1.hour.ago)
                         .where.not(duration_ms: nil)
                         .limit(100) # Sample size limit

    return nil if recent_events.count < 5 # Need at least 5 samples

    recent_events.average(:duration_ms)
  end
end
