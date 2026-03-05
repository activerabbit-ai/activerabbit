class PerfRollup < ApplicationRecord
  # Multi-tenancy setup - PerfRollup belongs to Account (tenant)
  acts_as_tenant(:account)

  belongs_to :project

  validates :timeframe, inclusion: { in: %w[minute hour day] }
  validates :timestamp, presence: true
  validates :target, presence: true  # controller#action or job class

  scope :for_timeframe, ->(timeframe) { where(timeframe: timeframe) }
  scope :for_timerange, ->(start_time, end_time) { where(timestamp: start_time..end_time) }
  scope :for_target, ->(target) { where(target: target) }

  def self.rollup_minute_data!
    # Process performance events from the last 2 minutes to handle any delays.
    # Uses a single SQL aggregation query instead of N+1 Ruby loops.
    start_time = 2.minutes.ago.beginning_of_minute
    end_time = 1.minute.ago.end_of_minute

    # Single query: aggregate all stats per (project, target, environment, minute)
    aggregated = PerformanceEvent
      .where(occurred_at: start_time..end_time)
      .where.not(duration_ms: nil)
      .select(
        :project_id,
        :target,
        :environment,
        "date_trunc('minute', occurred_at) AS truncated_ts",
        "COUNT(*) AS req_count",
        "AVG(duration_ms) AS avg_dur",
        "MIN(duration_ms) AS min_dur",
        "MAX(duration_ms) AS max_dur",
        "PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duration_ms) AS p50_dur",
        "PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms) AS p95_dur",
        "PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms) AS p99_dur"
      )
      .group(:project_id, :target, :environment, "date_trunc('minute', occurred_at)")

    return if aggregated.empty?

    # Batch-count related errors in a single query for the same time window.
    # Groups by (project_id, controller_action, environment, minute) so we
    # can look up the count per rollup row without N+1 queries.
    error_counts = Event.joins(:issue)
      .where(occurred_at: start_time..end_time)
      .group(
        :project_id,
        :controller_action,
        :environment,
        "date_trunc('minute', occurred_at)"
      )
      .count

    # Bulk upsert rollups
    aggregated.each do |row|
      # Look up the pre-computed error count for this (project, target, env, minute)
      ec = error_counts[[row.project_id, row.target, row.environment, row.truncated_ts]] || 0

      rollup = find_or_initialize_by(
        project_id: row.project_id,
        timeframe: "minute",
        timestamp: row.truncated_ts,
        target: row.target,
        environment: row.environment
      )

      rollup.assign_attributes(
        request_count: row.req_count,
        avg_duration_ms: row.avg_dur,
        p50_duration_ms: row.p50_dur,
        p95_duration_ms: row.p95_dur,
        p99_duration_ms: row.p99_dur,
        min_duration_ms: row.min_dur,
        max_duration_ms: row.max_dur,
        error_count: ec,
        hdr_histogram: nil
      )

      begin
        rollup.save!
      rescue Sidekiq::Shutdown
        Rails.logger.info "Sidekiq shutdown detected, stopping rollup processing"
        break
      end
    end
  end

  def self.rollup_hourly_data!
    # Rollup minute data into hourly
    start_time = 2.hours.ago.beginning_of_hour
    end_time = 1.hour.ago.end_of_hour

    where(timeframe: "minute")
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
        timeframe: "minute",
        target: target,
        environment: environment,
        timestamp: timestamp..(timestamp + 1.hour)
      )

      next if minute_rollups.empty?

      # Aggregate minute data
      total_requests = minute_rollups.sum(:request_count)
      total_duration = minute_rollups.sum("avg_duration_ms * request_count")

      rollup = find_or_initialize_by(
        project_id: project_id,
        timeframe: "hour",
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
