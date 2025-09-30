class PricingController < ApplicationController
  layout "admin"
  before_action :authenticate_user!

  def show
    @account = current_user.account
    @current_plan_label = "Current plan"

    # Fetch subscription details for current user
    if @account&.active_subscription?
      @subscription = current_user.pay_subscriptions.active.first
      @current_plan_label = "Current plan" if @subscription
      @next_payment_date = calculate_next_payment_date(@subscription)
    end
  end

  private

  def calculate_next_payment_date(subscription)
    return nil unless subscription&.current_period_end

    # Calculate next payment date based on current period end
    current_period_end = subscription.current_period_end
    next_payment_date = if current_period_end > Time.current
      current_period_end + 1.month
    else
      Time.current + 1.month
    end

    next_payment_date.strftime('%B %d, %Y')
  end
end
