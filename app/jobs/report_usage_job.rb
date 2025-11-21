class ReportUsageJob < ApplicationJob
  queue_as :default

  def perform(account_id:, day: Date.current)
    account = Account.find_by(id: account_id)
    return unless account

    # Aggregate daily resource usage
    DailyResourceUsage.aggregate_for_account_and_day(account_id, day)

    # Report to Stripe if needed
    UsageReporter.new(account:).report_daily!
    report_ai_overage!(account)
  end

  private

  # AI base includes 500 requests; report metered units for additional 1,000-blocks
  def report_ai_overage!(account)
    sub_item = account.ai_overage_subscription_item_id
    return unless sub_item.present?

    # Aggregate current period AI requests
    start_at = account.event_usage_period_start || Time.current.beginning_of_month
    end_at   = account.event_usage_period_end || Time.current.end_of_month
    used = AiRequest.where(account_id: account.id, occurred_at: start_at..end_at).count
    over = [used - 500, 0].max
    units = (over.to_f / 1000).ceil
    return if units <= 0

    Stripe::UsageRecord.create(
      subscription_item: sub_item,
      quantity: units,
      timestamp: Time.current.to_i,
      action: "set"
    )
  end
end
