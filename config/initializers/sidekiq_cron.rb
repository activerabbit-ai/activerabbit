require "sidekiq"
require "sidekiq-cron"

# Configure recurring jobs for performance rollups
# Temporarily disabled until PerformanceEvent data is available
# Sidekiq::Cron::Job.load_from_hash({
#   'minute_rollup' => {
#     'cron' => '* * * * *', # Every minute
#     'class' => 'PerfRollupJob',
#     'args' => ['minute']
#   },
#   'hourly_rollup' => {
#     'cron' => '5 * * * *', # 5 minutes past every hour
#     'class' => 'PerfRollupJob',
#     'args' => ['hour']
#   }
# }) if defined?(Sidekiq::Cron)

if defined?(Sidekiq::Cron) && ENV["REDIS_URL"].present?
  jobs = {
    "report_usage_daily" => {
      "cron" => "0 1 * * *",
      "class" => "ReportUsageDailyLoader"
    }
  }

  Sidekiq::Cron::Job.load_from_hash(jobs)
end

# Loader job to enqueue per-account usage reporting
class ReportUsageDailyLoader
  include Sidekiq::Worker
  def perform
    Account.find_each do |account|
      ReportUsageJob.perform_later(account_id: account.id)
    end
  end
end
