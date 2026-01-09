class PerfRollupJob
  include Sidekiq::Job

  sidekiq_options queue: :analysis, retry: 2

  def perform(timeframe = "minute")
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
