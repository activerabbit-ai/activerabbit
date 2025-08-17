class PerformanceAlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 2

  def perform(event_id)
    event = Event.find(event_id)

    # Check performance-based alert rules
    AlertRule.check_performance_rules(event)

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Event not found for performance alert: #{event_id}"
  rescue => e
    Rails.logger.error "Error in performance alert job: #{e.message}"
    raise e
  end
end
