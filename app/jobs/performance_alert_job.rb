class PerformanceAlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 2

  def perform(event_id)
    # Load event without tenant, then set tenant to its account
    event = nil
    ActsAsTenant.without_tenant do
      event = Event.find(event_id)
    end

    ActsAsTenant.with_tenant(event.project.account) do
      # Check performance-based alert rules within correct tenant
      AlertRule.check_performance_rules(event)
    end

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Event not found for performance alert: #{event_id}"
  rescue => e
    Rails.logger.error "Error in performance alert job: #{e.message}"
    raise e
  end
end
