# frozen_string_literal: true

class DataRetentionJob < ApplicationJob
  queue_as :default

  RETENTION_DAYS = 31
  BATCH_SIZE = 50_000  # Larger batches since we have indexes on occurred_at

  # Delete events and performance events older than 31 days
  # Runs daily via Sidekiq Cron
  #
  # Performance notes for large datasets (millions of rows):
  # - Uses raw SQL DELETE with LIMIT for efficiency (avoids Rails subquery)
  # - Batch size of 50K balances speed vs lock duration
  # - Both tables have indexes on occurred_at
  # - Expected: ~2-3 minutes for 6M rows
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
    delete_in_batches("events", cutoff_date)
  end

  def delete_old_performance_events(cutoff_date)
    delete_in_batches("performance_events", cutoff_date)
  end

  # Efficient batch deletion using raw SQL
  # PostgreSQL doesn't support DELETE with LIMIT directly, so we use a subquery
  # with ctid (tuple identifier) which is faster than id-based subqueries
  def delete_in_batches(table_name, cutoff_date)
    total_deleted = 0
    sanitized_cutoff = ActiveRecord::Base.connection.quote(cutoff_date.utc)

    loop do
      # Use ctid-based deletion which is very efficient in PostgreSQL
      # This avoids the overhead of Rails' limit().delete_all which generates
      # a slower id IN (SELECT id ...) query
      sql = <<-SQL.squish
        DELETE FROM #{table_name}
        WHERE ctid IN (
          SELECT ctid FROM #{table_name}
          WHERE occurred_at < #{sanitized_cutoff}
          LIMIT #{BATCH_SIZE}
        )
      SQL

      result = ActiveRecord::Base.connection.execute(sql)
      deleted_count = result.cmd_tuples
      total_deleted += deleted_count

      break if deleted_count == 0

      Rails.logger.info "[DataRetention] Deleted batch of #{deleted_count} #{table_name} (total: #{total_deleted})"

      # Small sleep between batches to reduce database load
      sleep(0.1) if deleted_count == BATCH_SIZE
    end

    total_deleted
  end
end
