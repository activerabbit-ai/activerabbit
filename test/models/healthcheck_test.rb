require "test_helper"

class HealthcheckTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
  end

  # Associations

  test "belongs to project" do
    association = Healthcheck.reflect_on_association(:project)
    assert_equal :belongs_to, association.macro
  end

  test "belongs to account" do
    association = Healthcheck.reflect_on_association(:account)
    assert_equal :belongs_to, association.macro
  end

  # Validations

  test "validates presence of name" do
    healthcheck = Healthcheck.new(
      project: @project,
      account: @account,
      check_type: "http",
      status: "healthy"
    )
    refute healthcheck.valid?
    assert_includes healthcheck.errors[:name], "can't be blank"
  end

  test "validates check_type inclusion" do
    healthcheck = Healthcheck.new(
      project: @project,
      account: @account,
      name: "Test Check",
      check_type: "invalid_type",
      status: "healthy"
    )
    refute healthcheck.valid?
    assert healthcheck.errors[:check_type].present?
  end

  test "validates status inclusion" do
    healthcheck = Healthcheck.new(
      project: @project,
      account: @account,
      name: "Test Check",
      check_type: "http",
      status: "invalid_status"
    )
    refute healthcheck.valid?
    assert healthcheck.errors[:status].present?
  end

  test "allows valid check_types" do
    %w[http database redis sidekiq custom].each do |check_type|
      healthcheck = Healthcheck.new(
        project: @project,
        account: @account,
        name: "Test Check",
        check_type: check_type,
        status: "healthy",
        config: {}
      )
      assert healthcheck.valid?, "Expected #{check_type} to be valid"
    end
  end

  test "allows valid statuses" do
    %w[healthy warning critical unknown].each do |status|
      healthcheck = Healthcheck.new(
        project: @project,
        account: @account,
        name: "Test Check",
        check_type: "http",
        status: status,
        config: {}
      )
      assert healthcheck.valid?, "Expected #{status} to be valid"
    end
  end

  # Scopes

  test "healthy scope filters by status healthy" do
    healthy_check = healthchecks(:homepage)
    healthy_check.update!(status: "healthy")

    healthy_checks = Healthcheck.healthy
    assert healthy_checks.all? { |h| h.status == "healthy" }
  end

  test "critical scope filters by status critical" do
    critical_check = healthchecks(:unhealthy)
    critical_check.update!(status: "critical")

    critical_checks = Healthcheck.critical
    assert critical_checks.all? { |h| h.status == "critical" }
  end

  test "recent scope orders by last_checked_at desc" do
    checks = Healthcheck.recent.limit(5)
    last_checked_times = checks.map(&:last_checked_at).compact

    # Should be ordered descending (newest first)
    assert_equal last_checked_times.sort.reverse, last_checked_times
  end
end
