class PricingController < ApplicationController
  layout "admin"
  before_action :authenticate_user!

  def usage
    # Same as show but renders usage view
    @account = current_user.account
    @current_plan_label = "Current plan"

    if @account
      @usage_data_available = @account.usage_data_available?

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

    # Note: Plan page doesn't need usage data - only subscription info
    # Don't call set_usage_data here to avoid unnecessary queries

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

    # All usage data is now read from cached columns on the account (INSTANT!)
    # Cached data is updated hourly by UsageSnapshotJob

    # Get plan quotas and usage in one call (reads from cached columns)
    plan_quotas = @account.usage_summary

    # 30-day data - query directly from source tables for accuracy
    # (DailyResourceUsage may have gaps if jobs didn't run)
    thirty_days_ago = 30.days.ago
    
    ActsAsTenant.without_tenant do
      @events_last_30_days = Event.where(account_id: @account.id)
                                  .where("occurred_at >= ?", thirty_days_ago)
                                  .count
      
      @ai_summaries_last_30_days = Issue.where(account_id: @account.id)
                                        .where("ai_summary_generated_at >= ?", thirty_days_ago)
                                        .count
      
      @pull_requests_last_30_days = AiRequest.where(account_id: @account.id, request_type: "pull_request")
                                             .where("occurred_at >= ?", thirty_days_ago)
                                             .count
    end
    
    @requests_total_last_30_days = @events_last_30_days + @ai_summaries_last_30_days + @pull_requests_last_30_days

    # Event/Error tracking usage (from cached columns - instant!)
    @event_quota = plan_quotas[:events][:quota]
    @events_used = plan_quotas[:events][:used]
    @events_remaining = plan_quotas[:events][:remaining]

    # AI Summaries usage
    @ai_summaries_quota = plan_quotas[:ai_summaries][:quota]
    @ai_summaries_used = plan_quotas[:ai_summaries][:used]
    @ai_summaries_remaining = plan_quotas[:ai_summaries][:remaining]

    # Pull Requests usage
    @pull_requests_quota = plan_quotas[:pull_requests][:quota]
    @pull_requests_used = plan_quotas[:pull_requests][:used]
    @pull_requests_remaining = plan_quotas[:pull_requests][:remaining]

    # Uptime Monitors usage
    @uptime_monitors_quota = plan_quotas[:uptime_monitors][:quota]
    @uptime_monitors_used = plan_quotas[:uptime_monitors][:used]
    @uptime_monitors_remaining = plan_quotas[:uptime_monitors][:remaining]

    # Status Pages usage
    @status_pages_quota = plan_quotas[:status_pages][:quota]
    @status_pages_used = plan_quotas[:status_pages][:used]
    @status_pages_remaining = plan_quotas[:status_pages][:remaining]

    # Projects usage
    @projects_quota = plan_quotas[:projects][:quota]
    @projects_used = plan_quotas[:projects][:used]
    @projects_remaining = plan_quotas[:projects][:remaining]
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
