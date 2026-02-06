require "test_helper"

class PerformanceEventTest < ActiveSupport::TestCase
  # ingest_performance

  test "ingest_performance creates a performance event" do
    project = projects(:default)
    payload = {
      controller_action: "HomeController#index",
      duration_ms: 250.5,
      db_duration_ms: 80.1,
      view_duration_ms: 120.2,
      occurred_at: Time.current.iso8601,
      environment: "production"
    }

    assert_difference -> { PerformanceEvent.count }, 1 do
      PerformanceEvent.ingest_performance(project: project, payload: payload)
    end
  end

  # slow? and very_slow?

  test "slow? returns false for fast requests" do
    event = PerformanceEvent.new(duration_ms: 200)
    refute event.slow?
  end

  test "slow? returns true for slow requests" do
    event = PerformanceEvent.new(duration_ms: 1500)
    assert event.slow?
  end

  test "very_slow? returns true for very slow requests" do
    event = PerformanceEvent.new(duration_ms: 6000)
    assert event.very_slow?
  end
end
