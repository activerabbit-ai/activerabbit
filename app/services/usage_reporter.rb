class UsageReporter
  def initialize(account:)
    @account = account
  end

  # Option A: Report daily usage to Stripe metered overage subscription item
  def report_daily!
    sub_item = @account.overage_subscription_item_id
    return unless sub_item.present?

    today = Date.current
    count = DailyEventCount.find_by(account_id: @account.id, day: today)&.count.to_i
    units = (count.to_f / 100_000).ceil
    return if units <= 0

    Stripe::UsageRecord.create(
      subscription_item: sub_item,
      quantity: units,
      timestamp: Time.current.to_i,
      action: "set"
    )
  end
end
