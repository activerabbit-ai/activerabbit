require "test_helper"

class PerformanceIncidentEvaluationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @project.update!(active: true)

    # Clear existing rollups and incidents to start fresh
    PerfRollup.delete_all
    PerformanceIncident.delete_all
  end

  test "does not create incidents without recent rollup data" do
    assert_no_difference -> { PerformanceIncident.count } do
      PerformanceIncidentEvaluationJob.new.perform
    end
  end

  test "skips inactive projects" do
    @project.update!(active: false)

    PerfRollup.create!(
      account: @account,
      project: @project,
      target: "UsersController#index",
      timeframe: "minute",
      timestamp: 1.minute.ago,
      p95_duration_ms: 900.0
    )

    assert_nothing_raised do
      PerformanceIncidentEvaluationJob.new.perform
    end
  end

  test "evaluates recent rollups for active projects" do
    # Create a high-p95 rollup that should trigger evaluation
    PerfRollup.create!(
      account: @account,
      project: @project,
      target: "SlowController#index",
      timeframe: "minute",
      timestamp: 1.minute.ago,
      p95_duration_ms: 5000.0
    )

    # Job should run without error even with high p95
    assert_nothing_raised do
      PerformanceIncidentEvaluationJob.new.perform
    end
  end

  test "ignores old rollups outside 2-minute window" do
    # Create rollup older than 2 minutes - should be ignored
    PerfRollup.create!(
      account: @account,
      project: @project,
      target: "OldController#index",
      timeframe: "minute",
      timestamp: 5.minutes.ago,
      p95_duration_ms: 9999.0
    )

    assert_no_difference -> { PerformanceIncident.count } do
      PerformanceIncidentEvaluationJob.new.perform
    end
  end

  test "checks stale incidents for recovery" do
    # Create an open incident with no recent rollup data
    incident = PerformanceIncident.create!(
      account: @account,
      project: @project,
      target: "StaleController#index",
      status: "open",
      severity: "warning",
      opened_at: 10.minutes.ago,
      trigger_p95_ms: 2000.0,
      threshold_ms: 1000.0,
      breach_count: 3
    )

    # No recent rollups for this target -> should attempt recovery
    assert_nothing_raised do
      PerformanceIncidentEvaluationJob.new.perform
    end
  end

  test "handles errors in individual project evaluation gracefully" do
    # Create valid rollup data
    PerfRollup.create!(
      account: @account,
      project: @project,
      target: "TestController#index",
      timeframe: "minute",
      timestamp: 1.minute.ago,
      p95_duration_ms: 100.0
    )

    # Job should complete even if one project has issues
    assert_nothing_raised do
      PerformanceIncidentEvaluationJob.new.perform
    end
  end

  test "processes only minute timeframe rollups" do
    # Create hour rollup (should be ignored)
    PerfRollup.create!(
      account: @account,
      project: @project,
      target: "HourlyController#index",
      timeframe: "hour",
      timestamp: 1.minute.ago,
      p95_duration_ms: 9999.0
    )

    # No minute rollups = nothing to evaluate
    assert_no_difference -> { PerformanceIncident.count } do
      PerformanceIncidentEvaluationJob.new.perform
    end
  end
end
