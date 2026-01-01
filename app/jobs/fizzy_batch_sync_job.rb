class FizzyBatchSyncJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 3

  # force: true bypasses the fizzy_sync_enabled check (for manual syncs)
  def perform(project_id, force = false)
    project = ActsAsTenant.without_tenant { Project.find(project_id) }
    ActsAsTenant.current_tenant = project.account

    fizzy_service = FizzySyncService.new(project)

    unless fizzy_service.configured?
      Rails.logger.info "Fizzy sync skipped for project #{project.slug}: not configured"
      return
    end

    unless force || project.fizzy_sync_enabled?
      Rails.logger.info "Fizzy sync skipped for project #{project.slug}: auto-sync not enabled"
      return
    end

    issues = project.issues.where(status: "open")
    result = fizzy_service.sync_batch(issues, force: force)

    Rails.logger.info "Fizzy batch sync completed for project #{project.slug}: " \
                      "#{result[:synced]} synced, #{result[:failed]} failed"
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Project not found for Fizzy batch sync: #{project_id}"
    raise e
  rescue => e
    Rails.logger.error "Error in Fizzy batch sync for project #{project_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end
end
