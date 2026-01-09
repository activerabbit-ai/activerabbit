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
      "class" => "PerformanceIncidentEvaluationJob"
    },

    # Aggregate performance rollups (minute -> hour)
    "minute_rollup" => {
      "cron" => "* * * * *",  # Every minute
      "class" => "PerfRollupJob",
      "args" => ["minute"]
    },

    "hourly_rollup" => {
      "cron" => "5 * * * *",  # 5 minutes past every hour
      "class" => "PerfRollupJob",
      "args" => ["hour"]
    },

    # ========================================
    # Usage & Quota Management
    # ========================================

    "report_usage_daily" => {
      "cron" => "0 1 * * *",  # Daily at 1:00 AM - aggregate usage
      "class" => "ReportUsageDailyLoader"
    },

    "quota_alerts_daily" => {
      "cron" => "0 10 * * *",  # Daily at 10:00 AM - send quota alerts
      "class" => "QuotaAlertJob"
    },

    # ========================================
    # Reports
    # ========================================

    "weekly_report" => {
      "cron" => "0 9 * * 1",  # Every Monday at 9:00 AM
      "class" => "WeeklyReportJob"
    }
  }

  begin
    Sidekiq::Cron::Job.load_from_hash(jobs)
    Rails.logger.info("[Sidekiq::Cron] Loaded #{jobs.size} cron jobs: #{jobs.keys.join(', ')}")
  rescue StandardError => e
    Rails.logger.warn("[Sidekiq::Cron] Skipping job load: #{e.class}: #{e.message}")
  end
end
