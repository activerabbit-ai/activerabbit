require "sidekiq"
require "sidekiq-cron"

# Loader job to enqueue per-account usage reporting
class ReportUsageDailyLoader
  include Sidekiq::Worker
  def perform
    Account.find_each do |account|
      ReportUsageJob.perform_later(account_id: account.id)
    end
  end
end

if defined?(Sidekiq::Cron) && ENV["REDIS_URL"].present? && !ActiveModel::Type::Boolean.new.cast(ENV["DISABLE_SIDEKIQ_CRON"]) && !Rails.env.test?
  jobs = {
    # ========================================
    # Performance Monitoring (Sentry/AppSignal style)
    # ========================================

    # Evaluate p95 metrics every minute for performance incident detection
    # This enables OPEN/CLOSE notifications with warm-up periods
    "performance_incident_evaluation" => {
      "cron" => "* * * * *",  # Every minute
      "class" => "PerformanceIncidentEvaluationJob",
      "cron_timezone" => "America/Los_Angeles"
    },

    # Aggregate performance rollups (minute -> hour)
    "minute_rollup" => {
      "cron" => "* * * * *",  # Every minute
      "class" => "PerfRollupJob",
      "args" => ["minute"],
      "cron_timezone" => "America/Los_Angeles"
    },

    "hourly_rollup" => {
      "cron" => "5 * * * *",  # 5 minutes past every hour PST
      "class" => "PerfRollupJob",
      "args" => ["hour"],
      "cron_timezone" => "America/Los_Angeles"
    },

    # ========================================
    # Usage & Quota Management
    # ========================================

    "report_usage_daily" => {
      "cron" => "0 1 * * *",  # Daily at 1:00 AM PST - aggregate usage
      "class" => "ReportUsageDailyLoader",
      "cron_timezone" => "America/Los_Angeles"
    },

    "usage_snapshot_hourly" => {
      "cron" => "0 * * * *",  # Every hour at minute 0 - cache usage for instant page loads
      "class" => "UsageSnapshotJob",
      "cron_timezone" => "America/Los_Angeles"
    },

    "quota_alerts_daily" => {
      "cron" => "0 10 * * *",  # Daily at 10:00 AM PST - send quota alerts
      "class" => "QuotaAlertJob",
      "cron_timezone" => "America/Los_Angeles"
    },

    "trial_reminder_daily" => {
      "cron" => "0 9 * * *",  # Daily at 9:00 AM PST - send trial ending reminders (8, 4, 2, 1, 0 days before & 2, 4, 6, 8 days after)
      "class" => "TrialReminderCheckJob",
      "cron_timezone" => "America/Los_Angeles"
    },

    "trial_expiration_daily" => {
      "cron" => "0 2 * * *",  # Daily at 2:00 AM PST - downgrade expired trials to Free plan
      "class" => "TrialExpirationJob",
      "cron_timezone" => "America/Los_Angeles"
    },

    # ========================================
    # Data Retention & Cleanup
    # ========================================

    "data_retention_daily" => {
      "cron" => "0 3 * * *",  # Daily at 3:00 AM PST - delete old data (5 days for free, 31 days for paid)
      "class" => "DataRetentionJob",
      "cron_timezone" => "America/Los_Angeles"
    },

    # ========================================
    # Reports
    # ========================================

    "weekly_report" => {
      "cron" => "0 9 * * 1",  # Every Monday at 9:00 AM PST
      "class" => "WeeklyReportJob",
      "cron_timezone" => "America/Los_Angeles"
    }
  }

  begin
    Sidekiq::Cron::Job.load_from_hash(jobs)
    Rails.logger.info("[Sidekiq::Cron] Loaded #{jobs.size} cron jobs: #{jobs.keys.join(', ')}")
  rescue StandardError => e
    Rails.logger.warn("[Sidekiq::Cron] Skipping job load: #{e.class}: #{e.message}")
  end
end
