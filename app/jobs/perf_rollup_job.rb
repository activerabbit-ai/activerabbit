class PerfRollupJob
  include Sidekiq::Job

  sidekiq_options queue: :analysis, retry: 2

  # Skip if the same timeframe is already running (prevents cron pile-up)
  LOCK_TTL = { "minute" => 90, "hour" => 600 }.freeze

  def perform(timeframe = "minute")
    lock_key = "lock:perf_rollup:#{timeframe}"
    ttl = LOCK_TTL.fetch(timeframe, 120)

    # Redis SET NX with TTL — only one instance runs at a time
    locked = Sidekiq.redis { |c| c.set(lock_key, Process.pid.to_s, nx: true, ex: ttl) }
    unless locked
      Rails.logger.info "[PerfRollupJob] Skipping #{timeframe} — already running"
      return
    end

    begin
      # Process rollups for each account with proper tenant context
      Account.find_each do |account|
        ActsAsTenant.with_tenant(account) do
          process_rollup_for_account(account, timeframe)
        end
      end

      Rails.logger.info "Completed #{timeframe} rollup processing for all accounts"
    rescue => e
      Rails.logger.error "Error in performance rollup (#{timeframe}): #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    ensure
      Sidekiq.redis { |c| c.del(lock_key) }
    end
  end

  private

  def process_rollup_for_account(account, timeframe)
    case timeframe
    when "minute"
      PerfRollup.rollup_minute_data!
    when "hour"
      PerfRollup.rollup_hourly_data!
    else
      raise ArgumentError, "Unknown timeframe: #{timeframe}"
    end
  rescue => e
    Rails.logger.error "Error in #{timeframe} rollup for account #{account.id}: #{e.message}"
    # Don't re-raise, continue processing other accounts
  end
end
