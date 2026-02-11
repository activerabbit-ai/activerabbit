require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    sign_in @user
    ActsAsTenant.current_tenant = @account
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "requires authentication" do
    sign_out @user
    get settings_path
    assert_redirected_to new_user_session_path
  end

  test "GET index" do
    get settings_path
    assert_response :success
    assert assigns(:settings).present?
    assert assigns(:account).present?
  end

  test "index shows account info" do
    get settings_path
    assert_response :success
    assert_equal "ActiveRabbit", assigns(:settings)[:app_name]
    assert_equal @account.name, assigns(:settings)[:account_name]
  end

  test "index shows total projects count" do
    get settings_path
    assert_response :success
    assert assigns(:settings)[:total_projects].is_a?(Integer)
  end

  test "index shows total users count" do
    get settings_path
    assert_response :success
    assert assigns(:settings)[:total_users].is_a?(Integer)
  end

  test "PATCH update_user_slack_preferences" do
    patch update_user_slack_preferences_settings_path, params: {
      preferences: {
        error_notifications: "1",
        performance_notifications: "0",
        n_plus_one_notifications: "1",
        new_issue_notifications: "1",
        personal_channel: "#my-alerts"
      }
    }

    assert_redirected_to settings_path
  end

  test "POST test_slack_notification without Slack configured" do
    @account.update!(slack_webhook_url: nil)

    post test_slack_notification_settings_path

    assert_redirected_to settings_path
    assert flash[:alert].present?
  end

  # Recent Deploys section

  test "index loads recent deploys" do
    get settings_path
    assert_response :success
    assert_not_nil assigns(:recent_deploys)
    assert assigns(:recent_deploys).is_a?(Array)
  end

  test "index shows deploys when present" do
    release = Release.create!(
      account: @account,
      project: projects(:default),
      version: "v#{SecureRandom.hex(4)}-settings-test",
      deployed_at: Time.current
    )
    Deploy.create!(
      account: @account,
      project: projects(:default),
      release: release,
      user: @user,
      started_at: Time.current,
      status: "completed"
    )

    get settings_path
    assert_response :success
    assert assigns(:recent_deploys).size >= 1
  end

  # Background Jobs section

  test "index loads sidekiq stats" do
    get settings_path
    assert_response :success
    assert_not_nil assigns(:sidekiq_stats)
    assert assigns(:sidekiq_stats).is_a?(Hash)
  end

  test "index handles sidekiq stats gracefully" do
    get settings_path
    assert_response :success

    stats = assigns(:sidekiq_stats)
    # Either has real stats or an error message (if Redis unavailable)
    assert stats[:processed].is_a?(Integer) || stats[:error].present?
  end
end
