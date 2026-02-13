# frozen_string_literal: true

# TrialExpirationJob runs daily and explicitly downgrades accounts
# to the Free plan when their trial has expired and they have no
# active subscription.
#
# This is the authoritative DB update — `effective_plan_key` provides
# dynamic fallback, but this job makes the change permanent so we
# don't depend on Stripe API availability for every page load.
#
# Runs via Sidekiq Cron daily at 2:00 AM PST.
#
# Only touches accounts where:
#   1. trial_ends_at is in the past
#   2. current_plan is NOT already "free"
#   3. No active Pay::Subscription exists for any user in the account
class TrialExpirationJob < ApplicationJob
  queue_as :default

  def perform
    # Use the existing scope that finds expired-trial accounts
    # without an active subscription and not already on free
    Account.needing_payment_reminder.where(active: true).find_each do |account|
      downgrade_to_free!(account)
    end
  end

  private

  def downgrade_to_free!(account)
    previous_plan = account.current_plan

    account.update!(
      current_plan: "free",
      event_quota: 5_000
    )

    Rails.logger.info(
      "[TrialExpiration] Downgraded account #{account.id} (#{account.name}) " \
      "from #{previous_plan} to free — trial expired at #{account.trial_ends_at}"
    )

    # Send a final notification that the downgrade happened
    begin
      LifecycleMailer.trial_expired_downgraded(account: account, previous_plan: previous_plan).deliver_now
    rescue => e
      Rails.logger.error "[TrialExpiration] Failed to send downgrade email for account #{account.id}: #{e.message}"
    end
  rescue => e
    Rails.logger.error "[TrialExpiration] Failed to downgrade account #{account.id}: #{e.message}"
  end
end
