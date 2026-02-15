# LifecycleMailer sends account lifecycle emails (welcome, trial, billing).
#
# IMPORTANT: These emails are ALWAYS sent regardless of user notification settings.
# Billing and lifecycle emails are critical and cannot be disabled by users.
# Only requirement: user must have confirmed their email address (or signed in via OAuth).
#
class LifecycleMailer < ApplicationMailer
  def welcome(account:)
    @account = account
    @user = confirmed_user_for(account)
    return unless @user

    mail to: @user.email, subject: "Welcome to ActiveRabbit"
  end

  def activation_tip(account:)
    @account = account
    @user = confirmed_user_for(account)
    return unless @user

    mail to: @user.email, subject: "Ship your first alert"
  end

  def trial_ending_soon(account:, days_left:)
    @account = account
    @days_left = days_left
    @user = confirmed_user_for(account)
    return unless @user

    mail to: @user.email, subject: "Trial ends in #{@days_left} days"
  end

  def trial_end_today(account:)
    @account = account
    @user = confirmed_user_for(account)
    return unless @user

    mail to: @user.email, subject: "Trial ends today"
  end

  def trial_expired_warning(account:, days_since_expired:)
    @account = account
    @days_since_expired = days_since_expired
    @user = confirmed_user_for(account)
    return unless @user

    mail to: @user.email, subject: "Your trial expired #{@days_since_expired} days ago — upgrade to Team"
  end

  def trial_expired_downgraded(account:, previous_plan:)
    @account = account
    @previous_plan = previous_plan
    @user = confirmed_user_for(account)
    return unless @user

    mail to: @user.email, subject: "Your account has been moved to the Free plan"
  end

  def payment_failed(account:, invoice_id:)
    @account = account
    @invoice_id = invoice_id
    @user = confirmed_user_for(account)
    return unless @user

    mail to: @user.email, subject: "Payment failed — update your card"
  end

  def card_expiring(account:)
    @account = account
    @user = confirmed_user_for(account)
    return unless @user

    mail to: @user.email, subject: "Your card is expiring soon"
  end

  def quota_nudge(account:, percent:)
    @account = account
    @percent = percent
    @user = confirmed_user_for(account)
    return unless @user

    mail to: @user.email, subject: "You're at #{@percent}% of your monthly quota"
  end

  def plan_upgraded(account:, new_plan:)
    @account = account
    @new_plan = new_plan
    @user = confirmed_user_for(account)
    return unless @user

    plan_label = @new_plan.to_s.titleize
    mail to: @user.email, subject: "Welcome to ActiveRabbit #{plan_label} — you're all set!"
  end

  private

  # Find the first user with a confirmed email in the account
  def confirmed_user_for(account)
    account.users.find(&:email_confirmed?)
  end
end
