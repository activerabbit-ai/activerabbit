require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  # Associations

  test "belongs to user optionally" do
    association = Project.reflect_on_association(:user)
    assert_equal :belongs_to, association.macro
    assert association.options[:optional]
  end

  test "has many issues with dependent destroy" do
    association = Project.reflect_on_association(:issues)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  test "has many events with dependent destroy" do
    association = Project.reflect_on_association(:events)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  test "has many perf_rollups with dependent destroy" do
    association = Project.reflect_on_association(:perf_rollups)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  test "has many releases with dependent destroy" do
    association = Project.reflect_on_association(:releases)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  test "has many api_tokens with dependent destroy" do
    association = Project.reflect_on_association(:api_tokens)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  test "has many healthchecks with dependent destroy" do
    association = Project.reflect_on_association(:healthchecks)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  test "has many alert_rules with dependent destroy" do
    association = Project.reflect_on_association(:alert_rules)
    assert_equal :has_many, association.macro
    assert_equal :destroy, association.options[:dependent]
  end

  # Validations

  test "validates presence of name" do
    project = Project.new(name: nil, environment: "production", url: "http://example.com", account: accounts(:default))
    refute project.valid?
    assert_includes project.errors[:name], "can't be blank"
  end

  test "validates presence of environment" do
    project = Project.new(name: "Test", environment: nil, url: "http://example.com", account: accounts(:default))
    refute project.valid?
    assert_includes project.errors[:environment], "can't be blank"
  end

  test "validates presence of url" do
    project = Project.new(name: "Test", environment: "production", url: nil, account: accounts(:default))
    refute project.valid?
    assert_includes project.errors[:url], "can't be blank"
  end

  test "validates URL format" do
    project = Project.new(name: "Test", environment: "production", url: "not-a-url", account: accounts(:default))
    refute project.valid?

    project.url = "https://example.com"
    assert project.valid?
  end

  test "generates slug from name when slug is not provided" do
    project = Project.new(name: "My Test Project", environment: "production", url: "http://example.com", account: accounts(:default))
    project.valid?
    assert_equal "my-test-project", project.slug
  end

  test "is valid without a user" do
    project = Project.new(name: "Test", environment: "production", url: "http://example.com", account: accounts(:default), user: nil)
    # Need unique slug
    project.slug = "test-no-user-#{SecureRandom.hex(4)}"
    assert project.valid?
  end

  # generate_api_token!

  test "generate_api_token creates a token and returns it" do
    project = projects(:default)
    assert_difference -> { project.api_tokens.count }, 1 do
      project.generate_api_token!
    end
    assert project.api_token.present?
  end

  # ---- Notifications: defaults ----

  test "notifications_enabled? defaults to true when settings are empty" do
    project = projects(:default)
    project.settings = {}
    assert project.notifications_enabled?
  end

  test "notifications_enabled? returns false when explicitly disabled" do
    project = projects(:default)
    project.settings = { "notifications" => { "enabled" => false } }
    refute project.notifications_enabled?
  end

  test "notifications_enabled? returns true when explicitly enabled" do
    project = projects(:default)
    project.settings = { "notifications" => { "enabled" => true } }
    assert project.notifications_enabled?
  end

  # ---- notify_via_email? ----

  test "notify_via_email? defaults to true when no channel settings exist" do
    project = projects(:default)
    project.settings = {}
    assert project.notify_via_email?
  end

  test "notify_via_email? returns true when explicitly enabled" do
    project = projects(:default)
    project.settings = { "notifications" => { "channels" => { "email" => true } } }
    assert project.notify_via_email?
  end

  test "notify_via_email? returns false when explicitly disabled" do
    project = projects(:default)
    project.settings = { "notifications" => { "channels" => { "email" => false } } }
    refute project.notify_via_email?
  end

  test "notify_via_email? returns false when notifications globally disabled" do
    project = projects(:default)
    project.settings = { "notifications" => { "enabled" => false, "channels" => { "email" => true } } }
    refute project.notify_via_email?
  end

  # ---- notify_via_slack? ----

  test "notify_via_slack? defaults to true when project has slack token and no channel settings" do
    project = projects(:with_slack)
    project.settings = {}
    assert project.notify_via_slack?
  end

  test "notify_via_slack? returns true when explicitly enabled" do
    project = projects(:with_slack)
    project.settings = { "notifications" => { "channels" => { "slack" => true } } }
    assert project.notify_via_slack?
  end

  test "notify_via_slack? returns false when explicitly disabled" do
    project = projects(:with_slack)
    project.settings = { "notifications" => { "channels" => { "slack" => false } } }
    refute project.notify_via_slack?
  end

  test "notify_via_slack? returns false when notifications globally disabled" do
    project = projects(:with_slack)
    project.settings = { "notifications" => { "enabled" => false, "channels" => { "slack" => true } } }
    refute project.notify_via_slack?
  end

  test "notify_via_slack? returns false when slack is not configured at all" do
    project = projects(:default)
    project.slack_access_token = nil
    # Also ensure account has no slack webhook
    project.account.settings = {}
    refute project.notify_via_slack?
  end

  # ---- slack_configured? checks account fallback ----

  test "slack_configured? returns true when project has slack token" do
    project = projects(:with_slack)
    assert project.slack_configured?
  end

  test "slack_configured? returns false when neither project nor account has slack" do
    project = projects(:default)
    project.slack_access_token = nil
    project.account.settings = {}
    refute project.slack_configured?
  end

  test "slack_configured? returns true when account has slack webhook even if project has no token" do
    project = projects(:default)
    project.slack_access_token = nil
    project.account.settings = { "slack_webhook_url" => "https://hooks.slack.com/services/test" }
    assert project.slack_configured?
  end

  test "notify_via_slack? works via account-level slack when project has no token" do
    project = projects(:default)
    project.slack_access_token = nil
    project.settings = {}
    project.account.settings = { "slack_webhook_url" => "https://hooks.slack.com/services/test" }
    assert project.notify_via_slack?
  end
end
