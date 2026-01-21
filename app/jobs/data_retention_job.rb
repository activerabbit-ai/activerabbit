# frozen_string_literal: true

class DataRetentionJob < ApplicationJob
  queue_as :default

  RETENTION_DAYS = 31

  # Delete events and performance events older than 31 days
  # Runs daily via Sidekiq Cron
  def perform
    cutoff_date = RETENTION_DAYS.days.ago

    Rails.logger.info "[DataRetention] Starting cleanup for records older than #{cutoff_date}"

    # Use ActsAsTenant.without_tenant to bypass tenant scoping for cleanup
    ActsAsTenant.without_tenant do
      events_deleted = delete_old_events(cutoff_date)
      performance_events_deleted = delete_old_performance_events(cutoff_date)

      Rails.logger.info "[DataRetention] Completed: deleted #{events_deleted} events, #{performance_events_deleted} performance events"
    end
  end

  private

  def delete_old_events(cutoff_date)
    total_deleted = 0

    # Delete in batches to avoid locking large portions of the table
    loop do
      deleted_count = Event.where("occurred_at < ?", cutoff_date).limit(10_000).delete_all
      total_deleted += deleted_count
      break if deleted_count == 0

      Rails.logger.info "[DataRetention] Deleted batch of #{deleted_count} events (total: #{total_deleted})"
    end

    total_deleted
  end

  def delete_old_performance_events(cutoff_date)
    total_deleted = 0

    # Delete in batches to avoid locking large portions of the table
    loop do
      deleted_count = PerformanceEvent.where("occurred_at < ?", cutoff_date).limit(10_000).delete_all
      total_deleted += deleted_count
      break if deleted_count == 0

      Rails.logger.info "[DataRetention] Deleted batch of #{deleted_count} performance events (total: #{total_deleted})"
    end

    total_deleted
  end
end
