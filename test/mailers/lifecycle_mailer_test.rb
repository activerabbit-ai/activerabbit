require "test_helper"

class LifecycleMailerTest < ActionMailer::TestCase
  setup do
    @account = accounts(:default)
    @account.update!(trial_ends_at: 14.days.from_now)
    @user = users(:owner)
  end

  # welcome

  test "welcome has correct subject" do
    mail = LifecycleMailer.welcome(account: @account)

    assert_equal "Welcome to ActiveRabbit", mail.subject
  end

  test "welcome sends to confirmed user" do
    mail = LifecycleMailer.welcome(account: @account)

    assert_equal [@user.email], mail.to
  end

  # activation_tip

  test "activation_tip has correct subject" do
    mail = LifecycleMailer.activation_tip(account: @account)

    assert_equal "Ship your first alert", mail.subject
  end

  # trial_ending_soon

  test "trial_ending_soon includes days left in subject" do
    mail = LifecycleMailer.trial_ending_soon(account: @account, days_left: 3)

    assert_equal "Trial ends in 3 days", mail.subject
  end

  # trial_end_today

  test "trial_end_today has correct subject" do
    mail = LifecycleMailer.trial_end_today(account: @account)

    assert_equal "Trial ends today", mail.subject
  end

  # payment_failed

  test "payment_failed has correct subject" do
    mail = LifecycleMailer.payment_failed(account: @account, invoice_id: "inv_123")

    assert_equal "Payment failed — update your card", mail.subject
  end

  # card_expiring

  test "card_expiring has correct subject" do
    mail = LifecycleMailer.card_expiring(account: @account)

    assert_equal "Your card is expiring soon", mail.subject
  end

  # quota_nudge

  test "quota_nudge includes percentage in subject" do
    mail = LifecycleMailer.quota_nudge(account: @account, percent: 75)

    assert_equal "You're at 75% of your monthly quota", mail.subject
  end
end
