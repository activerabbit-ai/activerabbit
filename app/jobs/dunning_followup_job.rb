class DunningFollowupJob < ApplicationJob
  queue_as :mailers

  def perform(account_id:, invoice_id:)
    account = Account.find_by(id: account_id)
    return unless account
    LifecycleMailer.payment_failed(account: account, invoice_id: invoice_id).deliver_now
  end
end
