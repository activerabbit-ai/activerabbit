class PerfRollup < ApplicationRecord
  belongs_to :project

  validates :timeframe, inclusion: { in: %w[minute hour day] }
  validates :timestamp, presence: true
  validates :target, presence: true  # controller#action or job class

  scope :for_timeframe, ->(timeframe) { where(timeframe: timeframe) }
  scope :for_timerange, ->(start_time, end_time) { where(timestamp: start_time..end_time) }
  scope :for_target, ->(target) { where(target: target) }

    def self.rollup_minute_data!
    require 'HDRHistogram'

    # Process performance events from the last 2 minutes to handle any delays
    start_time = 2.minutes.ago.beginning_of_minute
    end_time = 1.minute.ago.end_of_minute

    PerformanceEvent.for_timerange(start_time, end_time)
                   .select(:project_id, :target, :environment, "date_trunc('minute', occurred_at) as truncated_timestamp")
                   .group(:project_id, :target, :environment, "date_trunc('minute', occurred_at)")
                   .each do |grouped_event|
      project_id = grouped_event.project_id
      target = grouped_event.target
      environment = grouped_event.environment
      timestamp = grouped_event.truncated_timestamp

      events = PerformanceEvent.where(project_id: project_id)
                              .where(target: target)
                              .where(environment: environment)
                              .for_timerange(timestamp, timestamp + 1.minute)

      next if events.empty?

      durations = events.pluck(:duration_ms).compact
      next if durations.empty?

      # Create HDR histogram for accurate percentiles
      histogram = HDRHistogram.new(1, 60_000, 3) # 1ms to 60s, 3 significant digits

      durations.each do |duration|
        histogram.record_value([duration.to_i, 1].max) # Minimum 1ms
      end

      # Calculate percentiles from histogram
      p50 = histogram.value_at_percentile(50.0)
      p95 = histogram.value_at_percentile(95.0)
      p99 = histogram.value_at_percentile(99.0)

      # Count errors that occurred in the same timeframe
      error_count = Event.joins(:issue)
                         .where(project_id: project_id)
                         .where(controller_action: target)
                         .where(environment: environment)
                         .for_timerange(timestamp, timestamp + 1.minute)
                         .count

      # Create or update rollup
      rollup = find_or_initialize_by(
        project_id: project_id,
        timeframe: 'minute',
        timestamp: timestamp,
        target: target,
        environment: environment
      )

      rollup.assign_attributes(
        request_count: durations.size,
        avg_duration_ms: durations.sum.to_f / durations.size,
        p50_duration_ms: p50,
        p95_duration_ms: p95,
        p99_duration_ms: p99,
        min_duration_ms: histogram.min,
        max_duration_ms: histogram.max,
        error_count: error_count,
        hdr_histogram: histogram.serialize
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
      .select(:project_id, :target, :environment, "date_trunc('hour', timestamp) as truncated_timestamp")
      .group(:project_id, :target, :environment, "date_trunc('hour', timestamp)")
      .each do |grouped_rollup|
      project_id = grouped_rollup.project_id
      target = grouped_rollup.target
      environment = grouped_rollup.environment
      timestamp = grouped_rollup.truncated_timestamp

      minute_rollups = where(
        project_id: project_id,
        timeframe: 'minute',
        target: target,
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
        target: target,
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
        error_count: minute_rollups.sum(:error_count)
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
