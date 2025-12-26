class LifecycleMailer < ApplicationMailer
  def welcome(account:)
    @account = account
    mail to: account.users.first.email, subject: "Welcome to ActiveRabbit"
  end

  def activation_tip(account:)
    @account = account
    mail to: account.users.first.email, subject: "Ship your first alert"
  end

  def trial_ending_soon(account:, days_left:)
    @account = account
    @days_left = days_left
    mail to: account.users.first.email, subject: "Trial ends in #{@days_left} days"
  end

  def trial_end_today(account:)
    @account = account
    mail to: account.users.first.email, subject: "Trial ends today"
  end

  def payment_failed(account:, invoice_id:)
    @account = account
    @invoice_id = invoice_id
    mail to: account.users.first.email, subject: "Payment failed — update your card"
  end

  def card_expiring(account:)
    @account = account
    mail to: account.users.first.email, subject: "Your card is expiring soon"
  end

  def quota_nudge(account:, percent:)
    @account = account
    @percent = percent
    mail to: account.users.first.email, subject: "You're at #{@percent}% of your monthly quota"
  end
end
