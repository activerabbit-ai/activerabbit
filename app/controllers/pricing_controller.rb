class PricingController < ApplicationController
  layout "admin"
  before_action :authenticate_user!

  def show
    @account = current_user.account
    @current_plan_label = "Current plan"

    if @account
      @event_quota = (@account.event_quota.presence || @account.event_quota_value || 0).to_i
      @events_used = @account.events_used_in_billing_period
      @events_remaining = [@event_quota - @events_used, 0].max
    end

    if (pay_sub = @account&.active_subscription_record)
      @subscription = pay_sub
      @current_plan_label = "Current plan" if @subscription
      @next_payment_date = calculate_next_payment_date(@subscription)
      if @subscription
        @trial_days_left = calculate_trial_days_left(@subscription)
        @billing_period = format_billing_period(@subscription)
      end
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

    next_payment_date.strftime("%B %d, %Y")
  end

  def calculate_trial_days_left(subscription)
    return nil unless subscription.trial_ends_at

    days_left = (subscription.trial_ends_at.to_date - Date.current).to_i
    days_left.positive? ? days_left : nil
  end

  def format_billing_period(subscription)
    return nil unless subscription.current_period_start && subscription.current_period_end

    start_date = subscription.current_period_start.strftime("%B %d")
    end_date = subscription.current_period_end.strftime("%B %d")
    "#{start_date} – #{end_date}"
  end
end
