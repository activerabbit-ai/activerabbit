require "test_helper"

class AlertRulesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
    @alert_rule = alert_rules(:new_issue_rule)
    sign_in @user
    ActsAsTenant.current_tenant = @account
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "requires authentication" do
    sign_out @user
    get project_alert_rules_path(@project)
    assert_redirected_to new_user_session_path
  end

  test "POST create with valid params" do
    assert_difference "AlertRule.count", 1 do
      post project_alert_rules_path(@project), params: {
        alert_rule: {
          name: "Test Alert Rule #{SecureRandom.hex(4)}",
          rule_type: "error_frequency",
          threshold_value: 10,
          time_window_minutes: 60,
          cooldown_minutes: 15,
          enabled: true
        }
      }
    end

    assert_redirected_to project_alert_rules_path(@project)
  end

  test "DELETE destroy" do
    assert_difference "AlertRule.count", -1 do
      delete project_alert_rule_path(@project, @alert_rule)
    end

    assert_redirected_to project_alert_rules_path(@project)
  end

  test "POST toggle enables disabled rule" do
    @alert_rule.update!(enabled: false)

    post toggle_project_alert_rule_path(@project, @alert_rule)

    assert_redirected_to project_alert_rules_path(@project)
    @alert_rule.reload
    assert @alert_rule.enabled?
  end

  test "POST toggle disables enabled rule" do
    @alert_rule.update!(enabled: true)

    post toggle_project_alert_rule_path(@project, @alert_rule)

    assert_redirected_to project_alert_rules_path(@project)
    @alert_rule.reload
    refute @alert_rule.enabled?
  end
end
