class PerformanceAlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 2

  def perform(event_id)
    # Load event without tenant, then set tenant to its account
    event = nil
    ActsAsTenant.without_tenant do
      event = PerformanceEvent.unscoped.find_by(id: event_id)
    end

    unless event
      Rails.logger.warn "Event not found for performance alert: #{event_id}, skipping"
      return
    end

    project = nil
    ActsAsTenant.without_tenant do
      project = Project.unscoped.find_by(id: event.project_id)
    end

    unless project
      Rails.logger.warn "Project not found for performance alert: #{event.project_id}, skipping"
      return
    end

    # Check performance-based alert rules within correct tenant
    ActsAsTenant.with_tenant(project.account) do
      AlertRule.check_performance_rules(event)
    end

  rescue => e
    Rails.logger.error "Error in performance alert job: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end
end
