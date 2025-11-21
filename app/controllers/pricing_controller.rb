class PricingController < ApplicationController
  layout "admin"
  before_action :authenticate_user!

  def usage
    # Same as show but renders usage view
    @account = current_user.account
    @current_plan_label = "Current plan"

    if @account
      set_usage_data
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

  def show
    @account = current_user.account
    @current_plan_label = "Current plan"

    if @account
      set_usage_data
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

  def set_usage_data
    return unless @account

    # Event/Error tracking usage
    @event_quota = @account.event_quota_value
    @events_used = @account.events_used_in_billing_period
    @events_remaining = [@event_quota - @events_used, 0].max

    # AI Summaries usage
    @ai_summaries_quota = @account.ai_summaries_quota
    @ai_summaries_used = @account.ai_summaries_used_in_period
    @ai_summaries_remaining = [@ai_summaries_quota - @ai_summaries_used, 0].max

    # Pull Requests usage
    @pull_requests_quota = @account.pull_requests_quota
    @pull_requests_used = @account.pull_requests_used_in_period
    @pull_requests_remaining = [@pull_requests_quota - @pull_requests_used, 0].max

    # Uptime Monitors usage
    @uptime_monitors_quota = @account.uptime_monitors_quota
    @uptime_monitors_used = @account.uptime_monitors_used
    @uptime_monitors_remaining = [@uptime_monitors_quota - @uptime_monitors_used, 0].max

    # Status Pages usage
    @status_pages_quota = @account.status_pages_quota
    @status_pages_used = @account.status_pages_used
    @status_pages_remaining = [@status_pages_quota - @status_pages_used, 0].max

    # Projects usage
    @projects_quota = @account.projects_quota
    @projects_used = @account.projects_used
    @projects_remaining = [@projects_quota - @projects_used, 0].max
  end

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
