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
end
