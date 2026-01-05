class WeeklyReportBuilder
  def initialize(account)
    @account = account
    @period = 7.days.ago..Time.current
  end

  def build
    {
      period: @period,
      errors: top_errors,
      performance: slow_endpoints
    }
  end

  def top_errors
    Issue
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
      .group(:target)
      .select(
        "target,
        COUNT(*) AS requests,
        AVG(duration_ms) AS avg_ms,
        MAX(duration_ms) AS max_ms"
      )
      .order("avg_ms DESC")
      .limit(5)
  end
end
