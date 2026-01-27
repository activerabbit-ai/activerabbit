class WeeklyReportBuilder
  def initialize(account)
    @account = account
    # Previous calendar week: Monday 00:00:00 to Sunday 23:59:59
    # When run on Monday, reports the previous Mon-Sun (7 days exactly)
    @week_start = Date.current.beginning_of_week - 7.days
    @week_end = @week_start + 6.days
    @period = @week_start.beginning_of_day..@week_end.end_of_day
  end

  def build
    {
      period: @period,
      errors: top_errors,
      performance: slow_endpoints,
      errors_by_day: errors_by_day,
      performance_by_day: performance_by_day,
      total_errors: total_errors_count,
      total_performance: total_performance_count
    }
  end

  def top_errors
    Issue
      .includes(:project)
      .joins(:events)
      .where(account: @account)
      .where(events: { occurred_at: @period })
      .group("issues.id")
      .select(
        "issues.*,
         COUNT(events.id) AS occurrences,
         MAX(events.occurred_at) AS last_seen"
      )
      .order("occurrences DESC")
      .limit(5)
  end

  def slow_endpoints
    PerformanceEvent
      .where(account: @account)
      .where(occurred_at: @period)
      .group(:target, :project_id)
      .select(
        "target,
        project_id,
        COUNT(*) AS requests,
        AVG(duration_ms) AS avg_ms,
        MAX(duration_ms) AS max_ms"
      )
      .order("avg_ms DESC")
      .limit(5)
  end

  def errors_by_day
    # Get actual counts from database
    raw_counts = Event
      .where(account: @account)
      .where(occurred_at: @period)
      .group("DATE(events.occurred_at)")
      .count

    # Ensure all 7 days are present (Mon-Sun), with 0 for missing days
    fill_week_days(raw_counts)
  end

  def performance_by_day
    # Get actual counts from database
    raw_counts = PerformanceEvent
      .where(account: @account)
      .where(occurred_at: @period)
      .group("DATE(occurred_at)")
      .count

    # Ensure all 7 days are present (Mon-Sun), with 0 for missing days
    fill_week_days(raw_counts)
  end

  def total_errors_count
    Event
      .where(account: @account)
      .where(occurred_at: @period)
      .count
  end

  def total_performance_count
    PerformanceEvent
      .where(account: @account)
      .where(occurred_at: @period)
      .count
  end

  private

  # Fill in all 7 days of the week with counts (0 for missing days)
  # Returns an ordered hash: { Mon => count, Tue => count, ..., Sun => count }
  def fill_week_days(raw_counts)
    # Normalize keys to Date objects
    normalized = raw_counts.transform_keys do |key|
      key.is_a?(Date) ? key : Date.parse(key.to_s)
    end

    # Build ordered hash for Mon-Sun
    result = {}
    (0..6).each do |offset|
      date = @week_start + offset.days
      result[date] = normalized[date] || 0
    end
    result
  end
end
