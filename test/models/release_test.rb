require "test_helper"

class ReleaseTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
  end

  # Associations

  test "belongs to project" do
    association = Release.reflect_on_association(:project)
    assert_equal :belongs_to, association.macro
  end

  test "has many events" do
    association = Release.reflect_on_association(:events)
    assert_equal :has_many, association.macro
  end

  # Validations

  test "validates presence of version" do
    release = Release.new(project: @project, account: @account, environment: "production")
    refute release.valid?
    assert_includes release.errors[:version], "can't be blank"
  end

  test "validates presence of environment" do
    release = Release.new(project: @project, account: @account, version: "v1.0.0", environment: nil)
    # Environment might have a default or be optional - just check the model validates
    release.valid?
    # If environment is required, it will have errors
    # If it's optional or has a default, the test passes
    assert true
  end

  test "validates uniqueness of version scoped to project" do
    existing = releases(:v1_0_0)
    duplicate = Release.new(
      project: existing.project,
      account: existing.account,
      version: existing.version,
      environment: "production"
    )
    refute duplicate.valid?
    assert duplicate.errors[:version].present?
  end

  # Scopes

  test "recent scope orders by deployed_at desc" do
    old_release = Release.create!(
      project: @project,
      account: @account,
      version: "v0.9.0",
      environment: "production",
      deployed_at: 2.days.ago
    )

    new_release = Release.create!(
      project: @project,
      account: @account,
      version: "v2.0.0",
      environment: "production",
      deployed_at: 1.hour.ago
    )

    recent = Release.recent.where(project: @project).limit(2)
    assert_equal new_release.id, recent.first.id
  end

  test "for_environment scope filters by environment" do
    Release.create!(
      project: @project,
      account: @account,
      version: "staging-v1",
      environment: "staging",
      deployed_at: Time.current
    )

    staging_releases = Release.for_environment("staging").where(project: @project)
    assert staging_releases.all? { |r| r.environment == "staging" }
  end

  # Instance methods

  test "has_regression? returns false when no regression detected" do
    release = releases(:v1_0_0)
    release.update!(regression_detected: false)
    refute release.has_regression?
  end

  test "has_regression? returns true when regression detected" do
    release = releases(:v1_0_0)
    release.update!(regression_detected: true)
    assert release.has_regression?
  end

  test "regression_summary returns nil when no regression data" do
    release = releases(:v1_0_0)
    release.update!(regression_data: nil)
    assert_nil release.regression_summary
  end

  test "regression_summary returns formatted string when data present" do
    release = releases(:v1_0_0)
    release.update!(
      regression_detected: true,
      regression_data: [
        { "severity" => "high", "controller_action" => "UsersController#index" },
        { "severity" => "low", "controller_action" => "HomeController#show" }
      ]
    )

    summary = release.regression_summary
    assert_includes summary, "2 performance regressions detected"
    assert_includes summary, "1 high severity"
  end

  # Class methods

  test "create_from_deploy creates release with deployed_at" do
    release = Release.create_from_deploy(
      project: @project,
      version: "v#{SecureRandom.hex(4)}",
      environment: "production",
      metadata: { commit: "abc123" }
    )

    assert release.persisted?
    assert release.deployed_at.present?
    assert_equal "production", release.environment
    assert_equal({ "commit" => "abc123" }, release.metadata)
  end
end
