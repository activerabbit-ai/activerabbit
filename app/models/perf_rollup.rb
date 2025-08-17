class PerfRollup < ApplicationRecord
  belongs_to :project

  validates :timeframe, inclusion: { in: %w[minute hour day] }
  validates :timestamp, presence: true
  validates :controller_action, presence: true

  scope :for_timeframe, ->(timeframe) { where(timeframe: timeframe) }
  scope :for_timerange, ->(start_time, end_time) { where(timestamp: start_time..end_time) }
  scope :for_action, ->(action) { where(controller_action: action) }

  def self.rollup_minute_data!
    # Process events from the last 2 minutes to handle any delays
    start_time = 2.minutes.ago.beginning_of_minute
    end_time = 1.minute.ago.end_of_minute

    Event.performance
         .for_timerange(start_time, end_time)
         .group(:project_id, :controller_action, :environment)
         .group("date_trunc('minute', occurred_at)")
         .each do |(project_id, controller_action, environment, timestamp)|

      events = Event.performance
                   .where(project_id: project_id)
                   .where(controller_action: controller_action)
                   .where(environment: environment)
                   .for_timerange(timestamp, timestamp + 1.minute)

      next if events.empty?

      durations = events.pluck(:duration_ms).compact
      next if durations.empty?

      # Calculate percentiles
      sorted_durations = durations.sort
      count = sorted_durations.length

      p50 = percentile(sorted_durations, 50)
      p95 = percentile(sorted_durations, 95)
      p99 = percentile(sorted_durations, 99)

      # Create or update rollup
      rollup = find_or_initialize_by(
        project_id: project_id,
        timeframe: 'minute',
        timestamp: timestamp,
        controller_action: controller_action,
        environment: environment
      )

      rollup.assign_attributes(
        request_count: count,
        avg_duration_ms: durations.sum.to_f / count,
        p50_duration_ms: p50,
        p95_duration_ms: p95,
        p99_duration_ms: p99,
        min_duration_ms: sorted_durations.first,
        max_duration_ms: sorted_durations.last,
        error_count: events.joins(:issue).count,
        n_plus_one_count: events.where(n_plus_one_detected: true).count
      )

      rollup.save!
    end
  end

  def self.rollup_hourly_data!
    # Rollup minute data into hourly
    start_time = 2.hours.ago.beginning_of_hour
    end_time = 1.hour.ago.end_of_hour

    where(timeframe: 'minute')
      .for_timerange(start_time, end_time)
      .group(:project_id, :controller_action, :environment)
      .group("date_trunc('hour', timestamp)")
      .each do |(project_id, controller_action, environment, timestamp)|

      minute_rollups = where(
        project_id: project_id,
        timeframe: 'minute',
        controller_action: controller_action,
        environment: environment,
        timestamp: timestamp..(timestamp + 1.hour)
      )

      next if minute_rollups.empty?

      # Aggregate minute data
      total_requests = minute_rollups.sum(:request_count)
      total_duration = minute_rollups.sum('avg_duration_ms * request_count')

      rollup = find_or_initialize_by(
        project_id: project_id,
        timeframe: 'hour',
        timestamp: timestamp,
        controller_action: controller_action,
        environment: environment
      )

      rollup.assign_attributes(
        request_count: total_requests,
        avg_duration_ms: total_duration / total_requests,
        p50_duration_ms: minute_rollups.average(:p50_duration_ms),
        p95_duration_ms: minute_rollups.average(:p95_duration_ms),
        p99_duration_ms: minute_rollups.average(:p99_duration_ms),
        min_duration_ms: minute_rollups.minimum(:min_duration_ms),
        max_duration_ms: minute_rollups.maximum(:max_duration_ms),
        error_count: minute_rollups.sum(:error_count),
        n_plus_one_count: minute_rollups.sum(:n_plus_one_count)
      )

      rollup.save!
    end
  end

  private

  def self.percentile(sorted_array, percentile)
    return nil if sorted_array.empty?
    return sorted_array.first if sorted_array.length == 1

    index = (percentile / 100.0) * (sorted_array.length - 1)
    lower_index = index.floor
    upper_index = index.ceil

    if lower_index == upper_index
      sorted_array[lower_index]
    else
      lower_value = sorted_array[lower_index]
      upper_value = sorted_array[upper_index]
      weight = index - lower_index
      lower_value + weight * (upper_value - lower_value)
    end
  end
end
