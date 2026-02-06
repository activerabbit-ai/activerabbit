require "test_helper"

class AlertNotificationTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @alert_rule = alert_rules(:new_issue_rule)
  end

  # Associations

  test "belongs to alert_rule" do
    association = AlertNotification.reflect_on_association(:alert_rule)
    assert_equal :belongs_to, association.macro
  end

  test "belongs to project" do
    association = AlertNotification.reflect_on_association(:project)
    assert_equal :belongs_to, association.macro
  end

  # Validations

  test "validates notification_type inclusion" do
    notification = AlertNotification.new(
      alert_rule: @alert_rule,
      project: @project,
      account: @account,
      notification_type: "invalid",
      status: "pending"
    )
    refute notification.valid?
    assert notification.errors[:notification_type].present?
  end

  test "validates status inclusion" do
    notification = AlertNotification.new(
      alert_rule: @alert_rule,
      project: @project,
      account: @account,
      notification_type: "email",
      status: "invalid"
    )
    refute notification.valid?
    assert notification.errors[:status].present?
  end

  test "allows valid notification_types" do
    %w[slack email multi].each do |type|
      notification = AlertNotification.new(
        alert_rule: @alert_rule,
        project: @project,
        account: @account,
        notification_type: type,
        status: "pending",
        payload: {}
      )
      assert notification.valid?, "Expected #{type} to be valid"
    end
  end

  test "allows valid statuses" do
    %w[pending sent failed].each do |status|
      notification = AlertNotification.new(
        alert_rule: @alert_rule,
        project: @project,
        account: @account,
        notification_type: "email",
        status: status,
        payload: {}
      )
      assert notification.valid?, "Expected #{status} to be valid"
    end
  end

  # Scopes

  test "recent scope orders by created_at desc" do
    notifications = AlertNotification.recent.limit(5)
    created_times = notifications.map(&:created_at)
    assert_equal created_times.sort.reverse, created_times
  end

  test "by_status scope filters by status" do
    pending_notifications = AlertNotification.by_status("pending")
    assert pending_notifications.all? { |n| n.status == "pending" }
  end

  test "by_type scope filters by notification_type" do
    email_notifications = AlertNotification.by_type("email")
    assert email_notifications.all? { |n| n.notification_type == "email" }
  end

  # Instance methods

  test "mark_sent! updates status and sent_at" do
    notification = alert_notifications(:pending_notification)
    notification.mark_sent!

    assert_equal "sent", notification.status
    assert notification.sent_at.present?
  end

  test "mark_failed! updates status and error_message" do
    notification = alert_notifications(:pending_notification)
    notification.mark_failed!("Channel not found")

    assert_equal "failed", notification.status
    assert_equal "Channel not found", notification.error_message
    assert notification.failed_at.present?
  end
end
