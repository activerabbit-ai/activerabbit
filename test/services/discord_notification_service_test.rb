require "test_helper"

class DiscordNotificationServiceTest < ActiveSupport::TestCase
  setup do
    @project = projects(:default)
    @project.settings = (@project.settings || {}).merge(
      "discord_webhook_url" => "https://discord.com/api/webhooks/123/abc"
    )

    stub_request(:post, "https://discord.com/api/webhooks/123/abc")
      .to_return(status: 204, body: "", headers: {})
  end

  # configured?

  test "configured returns true when webhook URL is present" do
    service = DiscordNotificationService.new(@project)
    assert service.configured?
  end

  test "configured returns false when webhook URL is missing" do
    @project.settings = {}
    service = DiscordNotificationService.new(@project)
    refute service.configured?
  end

  # send_custom_alert

  test "send_custom_alert posts to Discord webhook" do
    service = DiscordNotificationService.new(@project)

    assert_nothing_raised do
      service.send_custom_alert("Test Alert", "Hello from ActiveRabbit", color: "good")
    end

    assert_requested :post, "https://discord.com/api/webhooks/123/abc"
  end

  test "send_custom_alert does nothing when not configured" do
    @project.settings = {}
    service = DiscordNotificationService.new(@project)

    assert_nothing_raised do
      service.send_custom_alert("Test", "Hello")
    end
  end

  # send_new_issue_alert

  test "send_new_issue_alert sends embed to Discord" do
    issue = issues(:open_issue)
    service = DiscordNotificationService.new(@project)

    assert_nothing_raised do
      service.send_new_issue_alert(issue)
    end

    assert_requested :post, "https://discord.com/api/webhooks/123/abc"
  end

  # send_error_frequency_alert

  test "send_error_frequency_alert sends embed to Discord" do
    issue = issues(:open_issue)
    payload = { "count" => 10, "time_window" => 5 }
    service = DiscordNotificationService.new(@project)

    assert_nothing_raised do
      service.send_error_frequency_alert(issue, payload)
    end

    assert_requested :post, "https://discord.com/api/webhooks/123/abc"
  end

  # Error handling

  test "gracefully handles webhook errors" do
    stub_request(:post, "https://discord.com/api/webhooks/123/abc")
      .to_return(status: 500, body: "Internal Server Error")

    service = DiscordNotificationService.new(@project)

    assert_nothing_raised do
      service.send_custom_alert("Test", "Should not raise")
    end
  end

  test "gracefully handles network errors" do
    stub_request(:post, "https://discord.com/api/webhooks/123/abc")
      .to_raise(Faraday::ConnectionFailed.new("Connection refused"))

    service = DiscordNotificationService.new(@project)

    assert_nothing_raised do
      service.send_custom_alert("Test", "Should not raise")
    end
  end
end
