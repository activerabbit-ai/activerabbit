require "test_helper"

class PerformanceIncidentTest < ActiveSupport::TestCase
  # Validations

  test "validates presence of target" do
    incident = PerformanceIncident.new(target: nil)
    refute incident.valid?
    assert_includes incident.errors[:target], "can't be blank"
  end

  test "validates presence of trigger_p95_ms" do
    incident = PerformanceIncident.new(trigger_p95_ms: nil)
    refute incident.valid?
    assert_includes incident.errors[:trigger_p95_ms], "can't be blank"
  end

  test "validates presence of threshold_ms" do
    incident = PerformanceIncident.new(threshold_ms: nil)
    refute incident.valid?
    assert_includes incident.errors[:threshold_ms], "can't be blank"
  end

  test "validates status inclusion" do
    incident = PerformanceIncident.new(status: "invalid")
    refute incident.valid?
    assert incident.errors[:status].present?
  end

  test "validates severity inclusion" do
    incident = PerformanceIncident.new(severity: "invalid")
    refute incident.valid?
    assert incident.errors[:severity].present?
  end

  # Associations

  test "belongs to project" do
    association = PerformanceIncident.reflect_on_association(:project)
    assert_equal :belongs_to, association.macro
  end

  # Scopes

  test "open scope returns open incidents" do
    open = performance_incidents(:open_warning)
    closed = performance_incidents(:closed_incident)

    assert_includes PerformanceIncident.open, open
    refute_includes PerformanceIncident.open, closed
  end

  test "closed scope returns closed incidents" do
    open = performance_incidents(:open_warning)
    closed = performance_incidents(:closed_incident)

    assert_includes PerformanceIncident.closed, closed
    refute_includes PerformanceIncident.closed, open
  end

  # find_open_incident

  test "find_open_incident finds open incident for target" do
    project = projects(:default)
    open = performance_incidents(:open_warning)

    result = PerformanceIncident.find_open_incident(project: project, target: open.target)
    assert_equal open, result
  end

  test "find_open_incident returns nil when no open incident" do
    project = projects(:default)

    result = PerformanceIncident.find_open_incident(project: project, target: "NonExistent#action")
    assert_nil result
  end

  # get_thresholds

  test "get_thresholds returns default thresholds" do
    project = projects(:default)
    thresholds = PerformanceIncident.get_thresholds(project, "UsersController#index")

    assert_equal PerformanceIncident::DEFAULT_WARNING_THRESHOLD_MS, thresholds[:warning]
    assert_equal PerformanceIncident::DEFAULT_CRITICAL_THRESHOLD_MS, thresholds[:critical]
    assert_equal PerformanceIncident::DEFAULT_WARMUP_COUNT, thresholds[:warmup_count]
    assert_equal PerformanceIncident::DEFAULT_COOLDOWN_MINUTES, thresholds[:cooldown_minutes]
  end

  test "get_thresholds respects project-level overrides" do
    project = projects(:default)
    project.update!(settings: {
      "performance_thresholds" => {
        "warning_ms" => 500,
        "critical_ms" => 1000
      }
    })

    thresholds = PerformanceIncident.get_thresholds(project, "UsersController#index")

    assert_equal 500.0, thresholds[:warning]
    assert_equal 1000.0, thresholds[:critical]
  end

  # duration_minutes

  test "duration_minutes calculates duration for closed incidents" do
    incident = performance_incidents(:closed_incident)
    # opened_at is 2 days ago, closed_at is 1 day ago
    assert incident.duration_minutes.positive?
  end

  test "duration_minutes returns nil for open incidents" do
    incident = performance_incidents(:open_warning)
    assert_nil incident.duration_minutes
  end

  # status_emoji

  test "status_emoji returns red for critical open incident" do
    incident = PerformanceIncident.new(status: "open", severity: "critical")
    assert_equal "🔴", incident.status_emoji
  end

  test "status_emoji returns yellow for warning open incident" do
    incident = PerformanceIncident.new(status: "open", severity: "warning")
    assert_equal "🟡", incident.status_emoji
  end

  test "status_emoji returns green for closed incident" do
    incident = PerformanceIncident.new(status: "closed")
    assert_equal "✅", incident.status_emoji
  end
end
