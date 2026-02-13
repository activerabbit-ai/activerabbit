# frozen_string_literal: true

# TrialReminderCheckJob runs daily to send trial-related reminders.
#
# BEFORE trial expires:
#   Sends "Trial ends in X days" at 8, 4, 2, 1 days before trial_ends_at.
#   Sends "Trial ends today" on the expiry day itself.
#
# AFTER trial expires (no subscription):
#   Sends "Trial expired X days ago — upgrade or switch to Free" at 2, 4, 6, 8 days after.
#
# Runs via Sidekiq Cron daily at 9:00 AM PST.
#
# Prevents duplicate emails by only matching exact day boundaries,
# so running once per day ensures each reminder is sent at most once.
class TrialReminderCheckJob < ApplicationJob
  queue_as :mailers

  # Days before trial end when we send pre-expiry reminders
  PRE_EXPIRY_DAYS = [8, 4, 2, 1].freeze

  # Days after trial end when we send post-expiry upgrade warnings
  POST_EXPIRY_DAYS = [2, 4, 6, 8].freeze

  def perform
    check_trial_ending_reminders
    check_trial_ends_today
    check_trial_expired_warnings
  end

  private

  # Send "Trial ends in X days" emails for accounts at 8, 4, 2, 1 days out
  def check_trial_ending_reminders
    PRE_EXPIRY_DAYS.each do |days_before|
      target_date = days_before.days.from_now.to_date

      accounts = Account.where(
        trial_ends_at: target_date.beginning_of_day..target_date.end_of_day
      ).where(active: true)

      accounts.find_each do |account|
        next if account.active_subscription?

        begin
          LifecycleMailer.trial_ending_soon(account: account, days_left: days_before).deliver_now
          Rails.logger.info "[TrialReminder] Sent #{days_before}-day pre-expiry reminder for account #{account.id} (#{account.name})"
        rescue => e
          Rails.logger.error "[TrialReminder] Failed to send #{days_before}-day pre-expiry reminder for account #{account.id}: #{e.message}"
        end
      end
    end
  end

  # Send "Trial ends today" email for accounts whose trial expires today
  def check_trial_ends_today
    today = Date.current

    accounts = Account.where(
      trial_ends_at: today.beginning_of_day..today.end_of_day
    ).where(active: true)

    accounts.find_each do |account|
      next if account.active_subscription?

      begin
        LifecycleMailer.trial_end_today(account: account).deliver_now
        Rails.logger.info "[TrialReminder] Sent trial-ends-today for account #{account.id} (#{account.name})"
      rescue => e
        Rails.logger.error "[TrialReminder] Failed to send trial-ends-today for account #{account.id}: #{e.message}"
      end
    end
  end

  # Send "Trial expired X days ago — upgrade or downgrade to Free" warnings
  # at 2, 4, 6, 8 days after trial expiry for accounts without a subscription
  def check_trial_expired_warnings
    POST_EXPIRY_DAYS.each do |days_after|
      target_date = days_after.days.ago.to_date

      accounts = Account.where(
        trial_ends_at: target_date.beginning_of_day..target_date.end_of_day
      ).where(active: true)

      accounts.find_each do |account|
        # Skip if they upgraded — they're paying, no warning needed
        next if account.active_subscription?

        begin
          LifecycleMailer.trial_expired_warning(account: account, days_since_expired: days_after).deliver_now
          Rails.logger.info "[TrialReminder] Sent #{days_after}-day post-expiry warning for account #{account.id} (#{account.name})"
        rescue => e
          Rails.logger.error "[TrialReminder] Failed to send #{days_after}-day post-expiry warning for account #{account.id}: #{e.message}"
        end
      end
    end
  end
end
