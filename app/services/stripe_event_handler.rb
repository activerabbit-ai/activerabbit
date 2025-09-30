class StripeEventHandler
  def initialize(event:)
    @event = event
    @type = event["type"]
    @data = event["data"]["object"]
  end

  def call
    case @type
    when "checkout.session.completed" then handle_checkout_completed
    when "customer.subscription.created", "customer.subscription.updated" then sync_subscription
    when "customer.subscription.deleted" then handle_subscription_deleted
    when "invoice.upcoming" then handle_invoice_upcoming
    when "invoice.finalized" then :noop
    when "invoice.payment_succeeded" then handle_payment_succeeded
    when "invoice.payment_failed" then handle_payment_failed
    when "customer.subscription.trial_will_end" then handle_trial_will_end
    else
      :noop
    end
  end

  private

  def account_from_customer
    customer_id = if @data.respond_to?(:customer)
      @data.customer
    else
      @data["customer"]
    end
    pay_customer = Pay::Customer.find_by(processor: "stripe", processor_id: customer_id)
    owner = pay_customer&.owner
    case owner
    when User
      owner.account
    when Account
      owner
    else
      nil
    end
  end

  def handle_checkout_completed
    # No-op: Pay will sync on subscription events.
  end

  def sync_subscription
    account = account_from_customer
    return unless account

    sub = @data
    trial_end = Time.at(sub.trial_end) if sub.respond_to?(:trial_end) && sub.trial_end
    current_period_start = Time.at(sub.current_period_start) if sub.respond_to?(:current_period_start) && sub.current_period_start
    current_period_end   = Time.at(sub.current_period_end) if sub.respond_to?(:current_period_end) && sub.current_period_end

    items = (sub.respond_to?(:items) && sub.items.respond_to?(:data)) ? sub.items.data : []
    base_item = items.find { |i| base_plan_price_ids.include?(i.price&.id) }
    ai_item   = items.find { |i| ai_price_ids.include?(i.price&.id) }
    overage_item = items.find { |i| i.price&.id == ENV["STRIPE_PRICE_OVERAGE_METERED"] }
    ai_overage_item = items.find { |i| i.price&.id == ENV["STRIPE_PRICE_AI_OVERAGE_METERED"] }

    plan, interval = plan_interval_from_price(base_item&.price&.id)

    account.update!(
      trial_ends_at: trial_end,
      current_plan: plan || account.current_plan,
      billing_interval: interval || account.billing_interval,
      ai_mode_enabled: ai_item.present?,
      event_quota: quota_for(plan || account.current_plan),
      event_usage_period_start: current_period_start,
      event_usage_period_end: current_period_end,
      overage_subscription_item_id: overage_item&.id,
      ai_overage_subscription_item_id: ai_overage_item&.id
    )

    # Ensure Pay subscription record exists/updated so UI can detect active status
    if (pay_customer = Pay::Customer.find_by(processor: "stripe", processor_id: sub.customer))
      pay_sub = Pay::Subscription.find_or_initialize_by(customer_id: pay_customer.id, processor_id: sub.id)
      pay_sub.name = pay_sub.name.presence || "default"
      pay_sub.processor_plan = base_item&.price&.id || pay_sub.processor_plan
      quantity = items.first&.quantity || 1
      pay_sub.quantity = quantity
      pay_sub.status = sub.status
      pay_sub.current_period_start = current_period_start
      pay_sub.current_period_end = current_period_end
      pay_sub.trial_ends_at = trial_end
      pay_sub.ends_at = Time.at(sub.ended_at) if sub.respond_to?(:ended_at) && sub.ended_at
      pay_sub.save!
    end
  end

  def handle_subscription_deleted
    if (account = account_from_customer)
      account.update!(ai_mode_enabled: false)
    end
    # Mark Pay subscription as canceled
    if (sub_id = @data["id"]).present?
      if (pay_sub = Pay::Subscription.find_by(processor_id: sub_id))
        pay_sub.update!(status: "canceled", ends_at: Time.current)
      end
    end
  end

  def handle_invoice_upcoming
    account = account_from_customer
    return unless account
    OverageCalculator.new(account:).attach_overage_invoice_item!(stripe_invoice: @data, customer_id: @data["customer"])
  end

  def handle_payment_succeeded
    account = account_from_customer
    return unless account
    settings = account.settings || {}
    if settings["past_due"]
      settings.delete("past_due")
      account.update(settings: settings)
    end

    # Also upsert Pay::Subscription using the invoice's subscription id
    subscription_id = if @data.respond_to?(:subscription)
      @data.subscription
    else
      @data["subscription"] || @data.dig("parent", "subscription_details", "subscription")
    end
    return unless subscription_id

    begin
      sub = Stripe::Subscription.retrieve(subscription_id)
      # Reuse subscription sync logic to ensure Pay::Subscription exists
      original_data = @data
      @data = sub
      sync_subscription
    ensure
      @data = original_data
    end
  end

  def handle_payment_failed
    account = account_from_customer
    return unless account
    # Mark past_due flag for feature restriction
    settings = account.settings || {}
    settings["past_due"] = true
    account.update(settings: settings)
    DunningFollowupJob.perform_later(account_id: account.id, invoice_id: @data["id"])
  end

  def handle_trial_will_end
    account = account_from_customer
    return unless account
    TrialEndingReminderJob.perform_later(account_id: account.id, at: Time.current)
  end

  def base_plan_price_ids
    [
      ENV["STRIPE_PRICE_DEV_MONTHLY"], ENV["STRIPE_PRICE_DEV_ANNUAL"],
      ENV["STRIPE_PRICE_TEAM_MONTHLY"], ENV["STRIPE_PRICE_TEAM_ANNUAL"],
      ENV["STRIPE_PRICE_ENT_MONTHLY"], ENV["STRIPE_PRICE_ENT_ANNUAL"]
    ].compact
  end

  def ai_price_ids
    [ ENV["STRIPE_PRICE_AI_MONTHLY"], ENV["STRIPE_PRICE_AI_ANNUAL"] ].compact
  end

  def plan_interval_from_price(price_id)
    case price_id
    when ENV["STRIPE_PRICE_DEV_MONTHLY"] then [ "developer", "month" ]
    when ENV["STRIPE_PRICE_DEV_ANNUAL"] then [ "developer", "year" ]
    when ENV["STRIPE_PRICE_TEAM_MONTHLY"] then [ "team", "month" ]
    when ENV["STRIPE_PRICE_TEAM_ANNUAL"] then [ "team", "year" ]
    when ENV["STRIPE_PRICE_ENT_MONTHLY"] then [ "enterprise", "month" ]
    when ENV["STRIPE_PRICE_ENT_ANNUAL"] then [ "enterprise", "year" ]
    else [ nil, nil ]
    end
  end

  def quota_for(plan)
    case plan
    when "developer" then 50_000
    when "team" then 100_000
    when "enterprise" then 5_000_000
    else 50_000
    end
  end
end
