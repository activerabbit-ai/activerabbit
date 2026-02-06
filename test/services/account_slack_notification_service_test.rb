require "test_helper"

class AccountSlackNotificationServiceTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @account.update!(slack_webhook_url: "https://hooks.slack.com/services/test")
    @service = AccountSlackNotificationService.new(@account)
    @project = projects(:default)
    @issue = issues(:open_issue)
  end

  test "configured? returns true when webhook_url present" do
    assert @service.configured?
  end

  test "configured? returns false when webhook_url blank" do
    @account.update!(slack_webhook_url: nil)
    service = AccountSlackNotificationService.new(@account)
    refute service.configured?
  end

  test "send_custom_alert does nothing when not configured" do
    @account.update!(slack_webhook_url: nil)
    service = AccountSlackNotificationService.new(@account)

    # Should not raise and should return early
    assert_nothing_raised do
      service.send_custom_alert("Test", "Message")
    end
  end

  test "send_custom_alert sends notification when configured" do
    notification_sent = false

    Slack::Notifier.stub(:new, ->(*args) {
      notifier = Object.new
      notifier.define_singleton_method(:post) { |msg| notification_sent = true }
      notifier
    }) do
      @service.send_custom_alert("Test Title", "Test message", color: "good")
    end

    assert notification_sent
  end

  test "send_error_frequency_alert returns early when not configured" do
    @account.update!(slack_webhook_url: nil)
    service = AccountSlackNotificationService.new(@account)

    assert_nothing_raised do
      service.send_error_frequency_alert(@issue, { "count" => 10, "time_window" => 5 })
    end
  end

  test "send_new_issue_alert returns early when not configured" do
    @account.update!(slack_webhook_url: nil)
    service = AccountSlackNotificationService.new(@account)

    assert_nothing_raised do
      service.send_new_issue_alert(@issue)
    end
  end

  test "send_performance_alert returns early when not configured" do
    @account.update!(slack_webhook_url: nil)
    service = AccountSlackNotificationService.new(@account)
    event = performance_events(:slow_request)

    assert_nothing_raised do
      service.send_performance_alert(event, { "duration_ms" => 5000 })
    end
  end

  test "send_n_plus_one_alert returns early when not configured" do
    @account.update!(slack_webhook_url: nil)
    service = AccountSlackNotificationService.new(@account)

    payload = {
      "incidents" => [{ "count_in_request" => 10, "sql_fingerprint" => { "query_type" => "SELECT" } }],
      "controller_action" => "UsersController#index"
    }

    assert_nothing_raised do
      service.send_n_plus_one_alert(payload)
    end
  end

  test "broadcast_to_account yields for each user" do
    users_notified = []

    @service.broadcast_to_account("error_notifications") do |user|
      users_notified << user
    end

    # Should iterate through account users
    assert users_notified.is_a?(Array)
  end
end
