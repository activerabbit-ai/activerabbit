require "test_helper"

class QuotaAlertMailerTest < ActionMailer::TestCase
  setup do
    @account = accounts(:free_account)
    @user = users(:owner)
    @account.update!(
      cached_events_used: 6000,
      usage_cached_at: Time.current
    )
  end

  # warning_80_percent

  test "warning_80_percent sends email to confirmed user" do
    @account.update!(cached_events_used: 4200) # 84% of 5000

    mail = QuotaAlertMailer.warning_80_percent(@account, :events)

    assert mail.present?
    assert_includes mail.subject, "84%"
    assert_includes mail.subject, "events"
  end

  # warning_90_percent

  test "warning_90_percent sends email to confirmed user" do
    @account.update!(cached_events_used: 4600) # 92% of 5000

    mail = QuotaAlertMailer.warning_90_percent(@account, :events)

    assert mail.present?
    assert_includes mail.subject, "92%"
  end

  # quota_exceeded

  test "quota_exceeded sends email with exceeded info" do
    mail = QuotaAlertMailer.quota_exceeded(@account, :events)

    assert mail.present?
    assert_includes mail.subject, "120%" # 6000/5000 = 120%
  end

  # quota_exceeded_reminder

  test "quota_exceeded_reminder sends reminder email" do
    mail = QuotaAlertMailer.quota_exceeded_reminder(@account, :events, 5)

    assert mail.present?
    assert_includes mail.subject, "events"
  end

  # free_plan_upgrade_reminder

  test "free_plan_upgrade_reminder sends upgrade reminder email" do
    mail = QuotaAlertMailer.free_plan_upgrade_reminder(@account, :events, 5)

    assert mail.present?
    assert_includes mail.subject, "Upgrade"
    assert_includes mail.subject, "events"
  end

  test "free_plan_upgrade_reminder includes upgrade messaging in body" do
    mail = QuotaAlertMailer.free_plan_upgrade_reminder(@account, :events, 5)

    assert_includes mail.body.encoded, "Free Plan"
    assert_includes mail.body.encoded, "Upgrade Plan"
  end

  # Different resource types

  test "handles events resource type" do
    mail = QuotaAlertMailer.warning_80_percent(@account, :events)
    assert mail.present?
  end

  test "handles ai_summaries resource type" do
    mail = QuotaAlertMailer.warning_80_percent(@account, :ai_summaries)
    assert mail.present?
  end

  test "handles pull_requests resource type" do
    mail = QuotaAlertMailer.warning_80_percent(@account, :pull_requests)
    assert mail.present?
  end
end
