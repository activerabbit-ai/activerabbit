class TrialEndingReminderJob < ApplicationJob
  queue_as :mailers

  def perform(account_id:, days_left: 4)
    account = Account.find_by(id: account_id)
    return unless account
    LifecycleMailer.trial_ending_soon(account: account, days_left: days_left).deliver_later
  end
end
