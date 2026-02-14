require "test_helper"

class SlackNotificationServiceTest < ActiveSupport::TestCase
  setup do
    @project = projects(:default)
    @project.update!(
      slack_access_token: "xoxb-test-token",
      slack_channel_id: "#alerts",
      slack_team_name: "Test Team"
    )

    # Stub Slack API
    stub_request(:post, "https://slack.com/api/chat.postMessage")
      .to_return(status: 200, body: '{"ok": true}', headers: { "Content-Type" => "application/json" })
  end

  # configured?

  test "configured returns true when token is present" do
    service = SlackNotificationService.new(@project)
    assert service.configured?
  end

  test "configured returns false when token is missing" do
    @project.update!(slack_access_token: nil)
    service = SlackNotificationService.new(@project)
    refute service.configured?
  end

  # send_blocks

  test "send_blocks does nothing when not configured" do
    @project.update!(slack_access_token: nil)
    service = SlackNotificationService.new(@project)

    # Should not raise error
    assert_nothing_raised do
      service.send_blocks(blocks: [], fallback_text: "Test")
    end
  end

  # send_new_issue_alert

  test "send_new_issue_alert sends message to Slack" do
    issue = issues(:open_issue)
    service = SlackNotificationService.new(@project)

    # The Slack API is stubbed in setup - just verify no errors
    assert_nothing_raised do
      service.send_new_issue_alert(issue)
    end
  end

  # send_error_frequency_alert

  test "send_error_frequency_alert sends message to Slack" do
    issue = issues(:open_issue)
    payload = { "count" => 10, "time_window" => 5 }
    service = SlackNotificationService.new(@project)

    # The Slack API is stubbed in setup - just verify no errors
    assert_nothing_raised do
      service.send_error_frequency_alert(issue, payload)
    end
  end

  # ===========================================================================
  # Free plan Slack blocking (project-level service)
  # ===========================================================================

  test "configured returns false when project belongs to free plan account" do
    free_project = projects(:free_project)
    free_project.update!(
      slack_access_token: "xoxb-test-token",
      slack_channel_id: "#alerts",
      slack_team_name: "Test Team"
    )
    service = SlackNotificationService.new(free_project)

    refute service.configured?,
      "Project on free plan account should not have Slack configured"
  end

  test "send_new_issue_alert does nothing for free plan project" do
    free_project = projects(:free_project)
    free_project.update!(
      slack_access_token: "xoxb-test-token",
      slack_channel_id: "#alerts",
      slack_team_name: "Test Team"
    )

    issue = issues(:open_issue)
    service = SlackNotificationService.new(free_project)

    # Should not raise and should return early without sending
    assert_nothing_raised do
      service.send_new_issue_alert(issue)
    end
  end
end
