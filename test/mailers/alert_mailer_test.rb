require "test_helper"

class AlertMailerTest < ActionMailer::TestCase
  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
  end

  # performance_incident_opened

  test "performance_incident_opened sends email to project recipients" do
    incident = performance_incidents(:open_warning)

    mail = AlertMailer.performance_incident_opened(project: @project, incident: incident)

    assert_includes mail.to, @user.email
  end

  test "performance_incident_opened includes warning emoji for warning severity" do
    incident = performance_incidents(:open_warning)

    mail = AlertMailer.performance_incident_opened(project: @project, incident: incident)

    assert_includes mail.subject, "🟡"
    assert_includes mail.subject, "WARNING"
  end

  test "performance_incident_opened includes critical emoji for critical severity" do
    incident = performance_incidents(:open_critical)

    mail = AlertMailer.performance_incident_opened(project: @project, incident: incident)

    assert_includes mail.subject, "🔴"
    assert_includes mail.subject, "CRITICAL"
  end

  test "performance_incident_opened includes endpoint in subject" do
    incident = performance_incidents(:open_warning)

    mail = AlertMailer.performance_incident_opened(project: @project, incident: incident)

    assert_includes mail.subject, incident.target
  end

  # performance_incident_resolved

  test "performance_incident_resolved includes resolved emoji" do
    incident = performance_incidents(:closed_incident)

    mail = AlertMailer.performance_incident_resolved(project: @project, incident: incident)

    assert_includes mail.subject, "✅"
  end

  test "performance_incident_resolved includes recovery info in body" do
    incident = performance_incidents(:closed_incident)

    mail = AlertMailer.performance_incident_resolved(project: @project, incident: incident)

    assert_includes mail.body.encoded, "resolved"
  end

  # send_alert

  test "send_alert sends alert email" do
    mail = AlertMailer.send_alert(
      to: @user.email,
      subject: "Test Alert",
      body: "Test body content",
      project: @project
    )

    assert_equal [@user.email], mail.to
    assert_equal "Test Alert", mail.subject
  end

  test "send_alert uses provided dashboard URL" do
    mail = AlertMailer.send_alert(
      to: @user.email,
      subject: "Test Alert",
      body: "Test body",
      project: @project,
      dashboard_url: "https://example.com/dashboard"
    )

    assert_includes mail.body.encoded, "https://example.com/dashboard"
  end
end
