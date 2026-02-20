# frozen_string_literal: true

class DataRetentionJob < ApplicationJob
  queue_as :default

  # Default retention for paid plans; free plan uses 5 days (from PLAN_QUOTAS)
  DEFAULT_RETENTION_DAYS = 31
  FREE_PLAN_RETENTION_DAYS = 5
  BATCH_SIZE = 50_000  # Larger batches since we have indexes on occurred_at

  # Delete events and performance events based on plan-specific retention.
  # Runs daily via Sidekiq Cron.
  #
  # Retention policy:
  #   - Free plan:  5 days  (data older than 5 days is deleted)
  #   - Paid plans: 31 days (data older than 31 days is deleted)
  #
  # Performance notes for large datasets (millions of rows):
  # - Uses raw SQL DELETE with LIMIT for efficiency (avoids Rails subquery)
  # - Batch size of 50K balances speed vs lock duration
  # - Both tables have indexes on occurred_at
  # - Expected: ~2-3 minutes for 6M rows
  def perform
    ActsAsTenant.without_tenant do
      # Phase 1: Delete old data for free-plan accounts (5 days)
      free_account_ids = free_plan_account_ids
      if free_account_ids.any?
        free_cutoff = FREE_PLAN_RETENTION_DAYS.days.ago
        Rails.logger.info "[DataRetention] Free plan cleanup (#{free_account_ids.size} accounts): records older than #{free_cutoff}"

        events_deleted = delete_old_events_for_accounts(free_cutoff, free_account_ids)
        perf_deleted = delete_old_performance_events_for_accounts(free_cutoff, free_account_ids)

        Rails.logger.info "[DataRetention] Free plan completed: deleted #{events_deleted} events, #{perf_deleted} performance events"
      end

      # Phase 2: Delete old data for ALL accounts (31 days global max)
      global_cutoff = DEFAULT_RETENTION_DAYS.days.ago
      Rails.logger.info "[DataRetention] Global cleanup: records older than #{global_cutoff}"

      events_deleted = delete_old_events(global_cutoff)
      perf_deleted = delete_old_performance_events(global_cutoff)

      Rails.logger.info "[DataRetention] Global completed: deleted #{events_deleted} events, #{perf_deleted} performance events"
    end
  end

  private

  # Find account IDs on the free plan (no active subscription, trial expired or never started)
  def free_plan_account_ids
    Account.where(current_plan: %w[free developer trial]).where(
      "trial_ends_at IS NULL OR trial_ends_at < ?", Time.current
    ).pluck(:id)
  end

  def delete_old_events(cutoff_date)
    delete_in_batches("events", cutoff_date)
  end

  def delete_old_performance_events(cutoff_date)
    delete_in_batches("performance_events", cutoff_date)
  end

  def delete_old_events_for_accounts(cutoff_date, account_ids)
    delete_in_batches_for_accounts("events", cutoff_date, account_ids)
  end

  def delete_old_performance_events_for_accounts(cutoff_date, account_ids)
    delete_in_batches_for_accounts("performance_events", cutoff_date, account_ids)
  end

  # Efficient batch deletion using raw SQL (global — all accounts)
  def delete_in_batches(table_name, cutoff_date)
    total_deleted = 0
    conn = ActiveRecord::Base.connection
    sanitized_table = conn.quote_table_name(table_name)
    sanitized_cutoff = conn.quote(cutoff_date.utc)

    loop do
      sql = <<-SQL.squish
        DELETE FROM #{sanitized_table}
        WHERE ctid IN (
          SELECT ctid FROM #{sanitized_table}
          WHERE occurred_at < #{sanitized_cutoff}
          LIMIT #{BATCH_SIZE}
        )
      SQL

      result = ActiveRecord::Base.connection.execute(sql)
      deleted_count = result.cmd_tuples
      total_deleted += deleted_count

      break if deleted_count == 0

      Rails.logger.info "[DataRetention] Deleted batch of #{deleted_count} #{table_name} (total: #{total_deleted})"
      sleep(0.1) if deleted_count == BATCH_SIZE
    end

    total_deleted
  end

  # Efficient batch deletion scoped to specific accounts (via project_id join)
  def delete_in_batches_for_accounts(table_name, cutoff_date, account_ids)
    total_deleted = 0
    conn = ActiveRecord::Base.connection
    sanitized_table = conn.quote_table_name(table_name)
    sanitized_cutoff = conn.quote(cutoff_date.utc)
    sanitized_ids = account_ids.map { |id| conn.quote(id) }.join(", ")

    loop do
      sql = <<-SQL.squish
        DELETE FROM #{sanitized_table}
        WHERE ctid IN (
          SELECT #{sanitized_table}.ctid FROM #{sanitized_table}
          INNER JOIN projects ON projects.id = #{sanitized_table}.project_id
          WHERE #{sanitized_table}.occurred_at < #{sanitized_cutoff}
          AND projects.account_id IN (#{sanitized_ids})
          LIMIT #{BATCH_SIZE}
        )
      SQL

      result = ActiveRecord::Base.connection.execute(sql)
      deleted_count = result.cmd_tuples
      total_deleted += deleted_count

      break if deleted_count == 0

      Rails.logger.info "[DataRetention] Deleted batch of #{deleted_count} #{table_name} for free accounts (total: #{total_deleted})"
      sleep(0.1) if deleted_count == BATCH_SIZE
    end

    total_deleted
  end
end
