require "test_helper"

class NotificationPreferenceTest < ActiveSupport::TestCase
  # Validations

  test "validates alert_type inclusion" do
    pref = NotificationPreference.new(project: projects(:default), alert_type: "invalid")
    refute pref.valid?
    assert pref.errors[:alert_type].present?
  end

  test "validates frequency inclusion" do
    pref = NotificationPreference.new(project: projects(:default), alert_type: "new_issue", frequency: "invalid")
    refute pref.valid?
    assert pref.errors[:frequency].present?
  end

  # Associations

  test "belongs to project" do
    association = NotificationPreference.reflect_on_association(:project)
    assert_equal :belongs_to, association.macro
  end

  # rate_limit_minutes

  test "rate_limit_minutes returns 5 for immediate" do
    pref = NotificationPreference.new(frequency: "immediate")
    assert_equal 5, pref.rate_limit_minutes
  end

  test "rate_limit_minutes returns 30 for every_30_minutes" do
    pref = NotificationPreference.new(frequency: "every_30_minutes")
    assert_equal 30, pref.rate_limit_minutes
  end

  test "rate_limit_minutes returns 120 for every_2_hours" do
    pref = NotificationPreference.new(frequency: "every_2_hours")
    assert_equal 120, pref.rate_limit_minutes
  end

  test "rate_limit_minutes returns 30 for first_in_deploy" do
    pref = NotificationPreference.new(frequency: "first_in_deploy")
    assert_equal 30, pref.rate_limit_minutes
  end

  # can_send_now?

  test "can_send_now returns false when disabled" do
    pref = NotificationPreference.new(enabled: false, frequency: "immediate")
    refute pref.can_send_now?
  end

  test "can_send_now returns true for immediate when enabled" do
    pref = NotificationPreference.new(enabled: true, frequency: "immediate")
    assert pref.can_send_now?
  end

  test "can_send_now returns true if never sent" do
    pref = NotificationPreference.new(enabled: true, frequency: "every_30_minutes", last_sent_at: nil)
    assert pref.can_send_now?
  end

  test "can_send_now returns true if sent more than rate limit ago" do
    pref = NotificationPreference.new(enabled: true, frequency: "every_30_minutes", last_sent_at: 31.minutes.ago)
    assert pref.can_send_now?
  end

  test "can_send_now returns false if sent within rate limit" do
    pref = NotificationPreference.new(enabled: true, frequency: "every_30_minutes", last_sent_at: 29.minutes.ago)
    refute pref.can_send_now?
  end

  test "can_send_now returns true for every_2_hours when sent more than 2 hours ago" do
    pref = NotificationPreference.new(enabled: true, frequency: "every_2_hours", last_sent_at: 121.minutes.ago)
    assert pref.can_send_now?
  end

  test "can_send_now returns false for every_2_hours when sent within 2 hours" do
    pref = NotificationPreference.new(enabled: true, frequency: "every_2_hours", last_sent_at: 119.minutes.ago)
    refute pref.can_send_now?
  end

  test "can_send_now returns true for first_in_deploy" do
    pref = NotificationPreference.new(enabled: true, frequency: "first_in_deploy")
    assert pref.can_send_now?
  end

  test "can_send_now returns true for after_close" do
    pref = NotificationPreference.new(enabled: true, frequency: "after_close")
    assert pref.can_send_now?
  end

  # frequency_description

  test "frequency_description includes immediately for immediate" do
    pref = NotificationPreference.new(frequency: "immediate")
    assert_includes pref.frequency_description, "immediately"
  end

  test "frequency_description includes 30 minutes for every_30_minutes" do
    pref = NotificationPreference.new(frequency: "every_30_minutes")
    assert_includes pref.frequency_description, "30 minutes"
  end

  test "frequency_description includes 2 hours for every_2_hours" do
    pref = NotificationPreference.new(frequency: "every_2_hours")
    assert_includes pref.frequency_description, "2 hours"
  end

  test "frequency_description includes deploy for first_in_deploy" do
    pref = NotificationPreference.new(frequency: "first_in_deploy")
    assert_includes pref.frequency_description, "deploy"
  end

  test "frequency_description includes recur for after_close" do
    pref = NotificationPreference.new(frequency: "after_close")
    assert_includes pref.frequency_description, "recur"
  end

  # mark_sent!

  test "mark_sent updates last_sent_at" do
    pref = notification_preferences(:new_issue_pref)
    assert_nil pref.last_sent_at

    pref.mark_sent!

    assert pref.reload.last_sent_at.present?
    assert_in_delta Time.current, pref.last_sent_at, 1.second
  end
end
