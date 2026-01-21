class PricingController < ApplicationController
  layout "admin"
  before_action :authenticate_user!

  def usage
    # Same as show but renders usage view
    @account = current_user.account
    @current_plan_label = "Current plan"

    if @account
      begin
        set_usage_data
        build_free_plan_comparison_if_on_trial!
      rescue => e
        Rails.logger.error "[PricingController#usage] Error loading usage data: #{e.class}: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        flash.now[:alert] = "Could not load some usage data. Please try again."
      end
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

    # Rolling 30-day usage window (for requests totals)
    window_start = 30.days.ago

    @events_last_30_days =
      Event.where("occurred_at > ?", window_start).count

    @ai_summaries_last_30_days =
      Issue.where("ai_summary_generated_at > ?", window_start).count

    @pull_requests_last_30_days =
      AiRequest.where(request_type: "pull_request")
               .where("occurred_at > ?", window_start)
               .count

    perf_requests_last_30_days =
      PerformanceEvent.where("occurred_at > ?", window_start).count

    @requests_total_last_30_days =
      @events_last_30_days + @ai_summaries_last_30_days + @pull_requests_last_30_days + perf_requests_last_30_days

    # Event/Error tracking usage (current billing period)
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

  # Build comparison data showing what the user's current usage would look like
  # against the Free plan limits. This is specifically for the /usage page so
  # that even during a 14‑day Team trial we can communicate:
  # "Your account is Free, and you've already used more than a Free plan allows."
  def build_free_plan_comparison_if_on_trial!
    return unless @account&.on_trial?

    free_quotas = ResourceQuotas::PLAN_QUOTAS[:free]

    @free_plan_usage = {
      events: {
        quota: free_quotas[:events],
        used: @events_used
      },
      ai_summaries: {
        quota: free_quotas[:ai_summaries],
        used: @ai_summaries_used
      },
      pull_requests: {
        quota: free_quotas[:pull_requests],
        used: @pull_requests_used
      },
      uptime_monitors: {
        quota: free_quotas[:uptime_monitors],
        used: @uptime_monitors_used
      },
      status_pages: {
        quota: free_quotas[:status_pages],
        used: @status_pages_used
      },
      projects: {
        quota: free_quotas[:projects],
        used: @projects_used
      }
    }

    @resources_exceeding_free =
      @free_plan_usage.select { |_key, data| data[:used].to_i > data[:quota].to_i }.keys
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
