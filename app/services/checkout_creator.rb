class CheckoutCreator
  Result = Struct.new(:url)

  def initialize(user:, account:, plan:, interval:, ai: false)
    @user = user
    @account = account
    @plan = plan # "developer"|"team"
    @interval = interval # "month"|"year"
    @ai = ActiveModel::Type::Boolean.new.cast(ai)
  end

  def call
    # Defensive: ensure API key is present even if initializers haven't set it
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"] if Stripe.api_key.nil? || Stripe.api_key.to_s.strip.empty?
    ensure_pay_customer!

    session = Stripe::Checkout::Session.create(
      mode: "subscription",
      customer: @user.payment_processor.processor_id,
      payment_method_collection: "if_required", # do NOT require card for free trial
      success_url: success_url,
      cancel_url: cancel_url,
      allow_promotion_codes: true,
      client_reference_id: @account.id,
      automatic_tax: { enabled: false },
      tax_id_collection: { enabled: false },
      subscription_data: {
        metadata: {
          account_id: @account.id,
          plan: @plan,
          interval: @interval,
          ai: @ai
        }
      },
      line_items: build_line_items
    )

    Result.new(session.url)
  end

  private

  def ensure_pay_customer!
    @user.set_payment_processor :stripe if @user.payment_processor.blank?
    if @user.payment_processor.processor_id.blank?
      stripe_customer = Stripe::Customer.create(
        email: @user.email,
        metadata: { user_id: @user.id, account_id: @account.id }
      )
      @user.payment_processor.update!(processor_id: stripe_customer.id)
    end
  end

  def build_line_items
    items = [{ price: price_for_plan(@plan, @interval), quantity: 1 }]
    if @ai
      items << { price: ai_base_price, quantity: 1 }
      items << { price: ENV.fetch("STRIPE_PRICE_AI_OVERAGE_METERED"), quantity: 1 }
    end
    items
  end

  def price_for_plan(plan, interval)
    case [plan, interval]
    when ["developer", "month"] then ENV.fetch("STRIPE_PRICE_DEV_MONTHLY")
    when ["developer", "year"]  then ENV.fetch("STRIPE_PRICE_DEV_ANNUAL")
    when ["team", "month"]      then ENV.fetch("STRIPE_PRICE_TEAM_MONTHLY")
    when ["team", "year"]       then ENV.fetch("STRIPE_PRICE_TEAM_ANNUAL")
    when ["enterprise", "month"] then ENV.fetch("STRIPE_PRICE_ENT_MONTHLY")
    when ["enterprise", "year"]  then ENV.fetch("STRIPE_PRICE_ENT_ANNUAL")
    else raise ArgumentError, "unknown plan/interval"
    end
  end

  def ai_base_price
    @interval == "year" ? ENV.fetch("STRIPE_PRICE_AI_ANNUAL") : ENV.fetch("STRIPE_PRICE_AI_MONTHLY")
  end

  def idempotency_key
    "checkout:#{@account.id}:#{@plan}:#{@interval}:#{@ai}"
  end

  def success_url
    host = ENV.fetch("APP_HOST")
    plan_q = CGI.escape(@plan.to_s)
    interval_q = CGI.escape(@interval.to_s)
    Rails.application.routes.url_helpers.dashboard_url(host: host) + "?subscribed=1&plan=#{plan_q}&interval=#{interval_q}"
  end

  def cancel_url
    Rails.application.routes.url_helpers.settings_url(host: ENV.fetch("APP_HOST")) + "?canceled=1"
  end
end
