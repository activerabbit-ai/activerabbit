require "test_helper"

class AlertJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)

    # Use existing or find/create alert rule for performance_regression
    @alert_rule = AlertRule.find_or_create_by!(
      account: @account,
      project: @project,
      rule_type: "performance_regression"
    ) do |rule|
      rule.name = "Test Alert"
      rule.threshold_value = 1000
      rule.time_window_minutes = 5
      rule.enabled = true
    end

    # Use existing or find/create notification preference (has uniqueness on project+alert_type)
    @preference = NotificationPreference.find_or_create_by!(
      project: @project,
      alert_type: "performance_regression"
    ) do |pref|
      pref.enabled = true
      pref.frequency = "every_2_hours"
    end
    @preference.update!(enabled: true, frequency: "every_2_hours", last_sent_at: nil)

    # Enable notifications for project
    @project.update!(settings: {
      "notifications" => {
        "enabled" => true,
        "channels" => { "email" => true }
      }
    })

    # Stub Resend API
    stub_request(:post, "https://api.resend.com/emails")
      .to_return(status: 200, body: '{"id": "test-email-id"}', headers: { "Content-Type" => "application/json" })
  end

  test "creates AlertNotification record when notifications enabled" do
    performance_event = PerformanceEvent.create!(
      account: @account,
      project: @project,
      target: "TestController#action",
      duration_ms: 5000,
      occurred_at: Time.current,
      environment: "production"
    )

    payload = {
      "event_id" => performance_event.id,
      "duration_ms" => 5000,
      "target" => "TestController#action"
    }

    assert_difference -> { AlertNotification.count }, 1 do
      AlertJob.new.perform(@alert_rule.id, "performance_regression", payload)
    end
  end

  test "marks preference as sent" do
    performance_event = PerformanceEvent.create!(
      account: @account,
      project: @project,
      target: "TestController#action",
      duration_ms: 5000,
      occurred_at: Time.current,
      environment: "production"
    )

    payload = {
      "event_id" => performance_event.id,
      "duration_ms" => 5000,
      "target" => "TestController#action"
    }

    assert_nil @preference.last_sent_at
    AlertJob.new.perform(@alert_rule.id, "performance_regression", payload)
    assert @preference.reload.last_sent_at.present?
  end

  test "does not create AlertNotification when frequency blocks sending" do
    @preference.update!(last_sent_at: 30.minutes.ago)

    performance_event = PerformanceEvent.create!(
      account: @account,
      project: @project,
      target: "TestController#action",
      duration_ms: 5000,
      occurred_at: Time.current,
      environment: "production"
    )

    payload = {
      "event_id" => performance_event.id,
      "duration_ms" => 5000,
      "target" => "TestController#action"
    }

    assert_no_difference -> { AlertNotification.count } do
      AlertJob.new.perform(@alert_rule.id, "performance_regression", payload)
    end
  end

  test "does not send when notifications disabled for project" do
    @project.update!(settings: { "notifications" => { "enabled" => false } })

    performance_event = PerformanceEvent.create!(
      account: @account,
      project: @project,
      target: "TestController#action",
      duration_ms: 5000,
      occurred_at: Time.current,
      environment: "production"
    )

    payload = {
      "event_id" => performance_event.id,
      "duration_ms" => 5000,
      "target" => "TestController#action"
    }

    assert_no_difference -> { AlertNotification.count } do
      AlertJob.new.perform(@alert_rule.id, "performance_regression", payload)
    end
  end
end
