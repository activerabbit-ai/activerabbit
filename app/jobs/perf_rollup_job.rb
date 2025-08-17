class PerfRollupJob
  include Sidekiq::Job

  sidekiq_options queue: :analysis, retry: 2

  def perform(timeframe = 'minute')
    case timeframe
    when 'minute'
      PerfRollup.rollup_minute_data!
      Rails.logger.info "Completed minute rollup processing"
    when 'hour'
      PerfRollup.rollup_hourly_data!
      Rails.logger.info "Completed hourly rollup processing"
    else
      raise ArgumentError, "Unknown timeframe: #{timeframe}"
    end
  rescue => e
    Rails.logger.error "Error in performance rollup (#{timeframe}): #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end
end
