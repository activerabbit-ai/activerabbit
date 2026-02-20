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
    # Support both real Stripe::Subscription objects and Hash payloads from tests
    trial_end_val = if sub.respond_to?(:trial_end)
      sub.trial_end
    else
      sub["trial_end"]
    end
    current_period_start_val = if sub.respond_to?(:current_period_start)
      sub.current_period_start
    else
      sub["current_period_start"]
    end
    current_period_end_val = if sub.respond_to?(:current_period_end)
      sub.current_period_end
    else
      sub["current_period_end"]
    end

    trial_end = Time.at(trial_end_val) if trial_end_val
    current_period_start = Time.at(current_period_start_val) if current_period_start_val
    current_period_end   = Time.at(current_period_end_val) if current_period_end_val

    items = if sub.respond_to?(:items) && sub.items.respond_to?(:data)
      sub.items.data
    else
      Array(sub["items"] && sub["items"]["data"])
    end
    base_item = items.find { |i| base_plan_price_ids.include?(i.respond_to?(:price) ? i.price&.id : i.dig("price", "id")) }
    ai_item   = items.find { |i| ai_price_ids.include?(i.respond_to?(:price) ? i.price&.id : i.dig("price", "id")) }
    overage_item = items.find do |i|
      (i.respond_to?(:price) ? i.price&.id : i.dig("price", "id")) == ENV["STRIPE_PRICE_OVERAGE_METERED"]
    end
    ai_overage_item = items.find do |i|
      (i.respond_to?(:price) ? i.price&.id : i.dig("price", "id")) == ENV["STRIPE_PRICE_AI_OVERAGE_METERED"]
    end

    base_price_id = if base_item.respond_to?(:price)
      base_item.price&.id
    else
      base_item && base_item.dig("price", "id")
    end
    plan, interval = plan_interval_from_price(base_price_id)

    sub_status = sub.respond_to?(:status) ? sub.status : sub["status"]
    subscription_billable = sub_status.in?(%w[active trialing])

    # Only upgrade the account plan when the subscription is actually
    # billable (active or trialing). Incomplete/past_due subscriptions
    # should NOT grant paid plan access — this prevents the bug where
    # a checkout that was never completed still sets current_plan.
    effective_plan = subscription_billable ? (plan || account.current_plan) : account.current_plan
    effective_interval = subscription_billable ? (interval || account.billing_interval) : account.billing_interval

    old_plan = account.current_plan
    new_plan = effective_plan
    plan_upgraded = old_plan.in?(%w[free trial]) && new_plan.in?(%w[team business])

    account_attrs = {
      ai_mode_enabled: subscription_billable && ai_item.present?,
      event_usage_period_start: current_period_start,
      event_usage_period_end: current_period_end,
      overage_subscription_item_id: if overage_item.respond_to?(:id)
        overage_item.id
                                    else
        overage_item && overage_item["id"]
                                    end,
      ai_overage_subscription_item_id: if ai_overage_item.respond_to?(:id)
        ai_overage_item.id
                                       else
        ai_overage_item && ai_overage_item["id"]
                                       end
    }

    if subscription_billable
      account_attrs[:trial_ends_at] = trial_end
      account_attrs[:current_plan] = effective_plan
      account_attrs[:billing_interval] = effective_interval
      account_attrs[:event_quota] = quota_for(effective_plan)
    end

    account.update!(**account_attrs)

    # Reset usage counters after plan upgrade so user starts fresh
    if plan_upgraded
      account.reset_usage_counters!
      Rails.logger.info("[StripeEventHandler] Plan upgraded from '#{old_plan}' to '#{new_plan}' — usage counters reset for account ##{account.id}")

      # Send welcome email for the new plan
      begin
        LifecycleMailer.plan_upgraded(account: account, new_plan: new_plan).deliver_later
      rescue => e
        Rails.logger.error("[StripeEventHandler] Failed to send plan upgrade email for account ##{account.id}: #{e.message}")
      end
    end

    # Ensure Pay subscription record exists/updated so UI can detect active status
    sub_customer_id = if sub.respond_to?(:customer)
      sub.customer
    else
      sub["customer"]
    end

    if (pay_customer = Pay::Customer.find_by(processor: "stripe", processor_id: sub_customer_id))
      sub_id = sub.respond_to?(:id) ? sub.id : sub["id"]
      pay_sub = Pay::Subscription.find_or_initialize_by(customer_id: pay_customer.id, processor_id: sub_id)
      pay_sub.name = pay_sub.name.presence || "default"
      pay_sub.processor_plan = base_price_id || pay_sub.processor_plan

      first_item = items.first
      quantity = if first_item.respond_to?(:quantity)
                   first_item.quantity
      else
                   first_item && first_item["quantity"]
      end
      pay_sub.quantity = quantity || 1
      pay_sub.status = sub.respond_to?(:status) ? sub.status : sub["status"]
      pay_sub.current_period_start = current_period_start
      pay_sub.current_period_end = current_period_end
      pay_sub.trial_ends_at = trial_end
      ended_at_val = if sub.respond_to?(:ended_at)
        sub.ended_at
      else
        sub["ended_at"]
      end
      pay_sub.ends_at = Time.at(ended_at_val) if ended_at_val
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

    # Stripe sends trial_will_end 3 days before trial expires.
    # Calculate actual days remaining from account's trial_ends_at.
    days_left = if account.trial_ends_at.present?
      ((account.trial_ends_at - Time.current) / 1.day).ceil.clamp(0, 30)
    else
      3 # Stripe default
    end

    TrialEndingReminderJob.perform_later(account_id: account.id, days_left: days_left)
  end

  def base_plan_price_ids
    [
      ENV["STRIPE_PRICE_TEAM_MONTHLY"], ENV["STRIPE_PRICE_TEAM_ANNUAL"],
      ENV["STRIPE_PRICE_BUSINESS_MONTHLY"], ENV["STRIPE_PRICE_BUSINESS_ANNUAL"]
    ].compact
  end

  def ai_price_ids
    [ENV["STRIPE_PRICE_AI_MONTHLY"], ENV["STRIPE_PRICE_AI_ANNUAL"]].compact
  end

  def plan_interval_from_price(price_id)
    case price_id
    when ENV["STRIPE_PRICE_TEAM_MONTHLY"] then ["team", "month"]
    when ENV["STRIPE_PRICE_TEAM_ANNUAL"] then ["team", "year"]
    when ENV["STRIPE_PRICE_BUSINESS_MONTHLY"] then ["business", "month"]
    when ENV["STRIPE_PRICE_BUSINESS_ANNUAL"] then ["business", "year"]
    else [nil, nil]
    end
  end

  def quota_for(plan)
    case plan
    when "team" then 50_000
    when "business" then 50_000
    else 10_000 # free plan default
    end
  end
end
