require "test_helper"

class PerfRollupTest < ActiveSupport::TestCase
  test "rollup_minute_data creates rollups from recent performance events" do
    project = projects(:default)
    now = Time.current.change(sec: 0)
    t1 = now - 90.seconds
    unique_target = "TestController#rollup_test_#{SecureRandom.hex(4)}"

    # Create performance events directly
    PerformanceEvent.create!(
      account: project.account,
      project: project,
      target: unique_target,
      occurred_at: t1,
      duration_ms: 200,
      environment: "production"
    )
    PerformanceEvent.create!(
      account: project.account,
      project: project,
      target: unique_target,
      occurred_at: t1 + 5.seconds,
      duration_ms: 400,
      environment: "production"
    )

    # Run rollup
    PerfRollup.rollup_minute_data!

    # Check that a rollup was created for our target
    rollup = PerfRollup.where(project: project, target: unique_target).last
    assert rollup.present?, "Expected rollup to be created for target"
    assert_equal "minute", rollup.timeframe
    assert rollup.request_count >= 2
    assert rollup.avg_duration_ms.between?(200, 400)
  end

  test "rollup_minute_data computes correct percentiles via SQL" do
    project = projects(:default)
    now = Time.current.change(sec: 0)
    # Pick a timestamp safely within a single minute boundary
    t1 = (now - 90.seconds).beginning_of_minute + 5.seconds
    unique_target = "TestController#percentile_#{SecureRandom.hex(4)}"

    # Create events with known durations all within the same minute
    durations = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    durations.each_with_index do |d, i|
      PerformanceEvent.create!(
        account: project.account,
        project: project,
        target: unique_target,
        occurred_at: t1 + i.seconds,
        duration_ms: d,
        environment: "production"
      )
    end

    PerfRollup.rollup_minute_data!

    rollup = PerfRollup.where(project: project, target: unique_target, timeframe: "minute").last
    assert rollup.present?, "Rollup should be created"
    assert_equal 10, rollup.request_count
    assert_in_delta 55.0, rollup.avg_duration_ms, 1.0
    assert_in_delta 10.0, rollup.min_duration_ms, 0.1
    assert_in_delta 100.0, rollup.max_duration_ms, 0.1
    # p50 should be ~55, p95 ~95.5, p99 ~99.1
    assert rollup.p50_duration_ms.between?(45.0, 65.0), "p50 should be around 55"
    assert rollup.p95_duration_ms.between?(85.0, 100.0), "p95 should be around 95"
    assert rollup.p99_duration_ms.between?(95.0, 100.0), "p99 should be around 99"
  end

  test "rollup_minute_data ignores events outside the 2-minute window" do
    project = projects(:default)
    unique_target = "TestController#old_#{SecureRandom.hex(4)}"

    # Event from 10 minutes ago — should be ignored
    PerformanceEvent.create!(
      account: project.account,
      project: project,
      target: unique_target,
      occurred_at: 10.minutes.ago,
      duration_ms: 999,
      environment: "production"
    )

    PerfRollup.rollup_minute_data!

    rollup = PerfRollup.where(project: project, target: unique_target, timeframe: "minute").last
    assert_nil rollup, "No rollup should be created for old events"
  end

  test "rollup_minute_data groups by environment" do
    project = projects(:default)
    now = Time.current.change(sec: 0)
    t1 = now - 90.seconds
    unique_target = "TestController#env_group_#{SecureRandom.hex(4)}"

    PerformanceEvent.create!(
      account: project.account, project: project, target: unique_target,
      occurred_at: t1, duration_ms: 100, environment: "production"
    )
    PerformanceEvent.create!(
      account: project.account, project: project, target: unique_target,
      occurred_at: t1, duration_ms: 500, environment: "staging"
    )

    PerfRollup.rollup_minute_data!

    prod_rollup = PerfRollup.where(project: project, target: unique_target, environment: "production").last
    staging_rollup = PerfRollup.where(project: project, target: unique_target, environment: "staging").last

    assert prod_rollup.present?, "Production rollup should exist"
    assert staging_rollup.present?, "Staging rollup should exist"
    assert_in_delta 100.0, prod_rollup.avg_duration_ms, 0.1
    assert_in_delta 500.0, staging_rollup.avg_duration_ms, 0.1
  end
end
