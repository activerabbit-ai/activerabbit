require 'sidekiq'
require 'sidekiq-cron'

# Configure recurring jobs for performance rollups
Sidekiq::Cron::Job.load_from_hash({
  'minute_rollup' => {
    'cron' => '* * * * *', # Every minute
    'class' => 'PerfRollupJob',
    'args' => ['minute']
  },
  'hourly_rollup' => {
    'cron' => '5 * * * *', # 5 minutes past every hour
    'class' => 'PerfRollupJob',
    'args' => ['hour']
  }
}) if defined?(Sidekiq::Cron)
