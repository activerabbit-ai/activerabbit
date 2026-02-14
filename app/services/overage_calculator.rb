class OverageCalculator
  CHUNK = 100_000
  PRICE_PER_CHUNK_CENTS = 1000

  def initialize(account:)
    @account = account
  end

  def attach_overage_invoice_item!(stripe_invoice:, customer_id:)
    # Free plan: hard-capped, no overage fees — skip entirely
    return if @account.respond_to?(:on_free_plan?) && @account.on_free_plan?

    period_start = Time.at(stripe_invoice["period_start"]) if stripe_invoice["period_start"]
    period_end   = Time.at(stripe_invoice["period_end"]) if stripe_invoice["period_end"]
    return unless period_start && period_end

    over_events = overage_events(period_start:, period_end:)
    chunks = (over_events.to_f / CHUNK).ceil
    return if chunks <= 0

    Stripe::InvoiceItem.create(
      customer: customer_id,
      invoice: stripe_invoice["id"],
      currency: "usd",
      amount: chunks * PRICE_PER_CHUNK_CENTS,
      description: "Overage: #{over_events} events (#{chunks} × 100k)"
    )
  end

  def overage_events(period_start:, period_end:)
    used = events_in_range(period_start:, period_end:)
    [used - quota_for_account, 0].max
  end

  def events_in_range(period_start:, period_end:)
    start_date = period_start.to_date
    end_date = period_end.to_date
    DailyEventCount.where(account_id: @account.id, day: start_date..end_date).sum(:count)
  end

  def quota_for_account
    return @account.event_quota if @account.respond_to?(:event_quota) && @account.event_quota.present?

    case @account.current_plan
    when "developer"  then 50_000
    when "team"       then 200_000
    when "enterprise" then 2_000_000
    else 50_000
    end
  end
end
