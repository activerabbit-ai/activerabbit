require "test_helper"

class PerformanceIncidentNotificationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @incident = performance_incidents(:open_warning)
    @project.update!(settings: { "notifications" => { "enabled" => true } })

    # Stub Slack API
    stub_request(:post, "https://slack.com/api/chat.postMessage")
      .to_return(status: 200, body: '{"ok": true}', headers: { "Content-Type" => "application/json" })
  end

  test "marks open notification as sent" do
    @project.update!(
      slack_access_token: "xoxb-test-token",
      slack_channel_id: "#alerts",
      settings: @project.settings.merge("notifications" => { "enabled" => true, "channels" => { "slack" => true } })
    )

    PerformanceIncidentNotificationJob.new.perform(@incident.id, "open")

    assert @incident.reload.open_notification_sent
  end

  test "does not send duplicate open notifications" do
    @incident.update!(open_notification_sent: true)
    @project.update!(
      slack_access_token: "xoxb-test-token",
      slack_channel_id: "#alerts",
      settings: @project.settings.merge("notifications" => { "enabled" => true, "channels" => { "slack" => true } })
    )

    assert_nothing_raised do
      PerformanceIncidentNotificationJob.new.perform(@incident.id, "open")
    end
  end

  test "marks close notification as sent" do
    closed_incident = performance_incidents(:closed_incident)
    @project.update!(
      slack_access_token: "xoxb-test-token",
      slack_channel_id: "#alerts",
      settings: @project.settings.merge("notifications" => { "enabled" => true, "channels" => { "slack" => true } })
    )

    PerformanceIncidentNotificationJob.new.perform(closed_incident.id, "close")

    assert closed_incident.reload.close_notification_sent
  end
end
