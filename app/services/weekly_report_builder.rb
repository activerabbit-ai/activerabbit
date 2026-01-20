class WeeklyReportBuilder
  def initialize(account)
    @account = account
    @period = 7.days.ago..Time.current
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
    Event
      .joins(:project)
      .where(account: @account)
      .where(occurred_at: @period)
      .group("DATE(events.occurred_at)")
      .order("DATE(events.occurred_at) ASC")
      .count
  end

  def performance_by_day
    PerformanceEvent
      .where(account: @account)
      .where(occurred_at: @period)
      .group("DATE(occurred_at)")
      .order("DATE(occurred_at) ASC")
      .count
  end

  def total_errors_count
    Event
      .joins(:project)
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
end
