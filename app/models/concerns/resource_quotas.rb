# frozen_string_literal: true

# ResourceQuotas concern handles all resource quota calculations and usage tracking
# for different subscription plans (free, team, business).
#
# Usage:
#   account.event_quota_value          # => 3000 (for free plan)
#   account.ai_summaries_used_in_period # => 3
#   account.within_quota?(:ai_summaries) # => true
#   account.usage_percentage(:pull_requests) # => 45.5
#
module ResourceQuotas
  extend ActiveSupport::Concern

  # Plan-based quota definitions
  PLAN_QUOTAS = {
    free: {
      events: 5_000,
      ai_summaries: 5,
      pull_requests: 5,
      uptime_monitors: 0,
      status_pages: 0,
      projects: 1
    },
    team: {
      events: 50_000,
      ai_summaries: 300,
      pull_requests: 100,
      uptime_monitors: 20,
      status_pages: 5,
      projects: 10
    },
    business: {
      events: 100_000,
      ai_summaries: 500,
      pull_requests: 250,
      uptime_monitors: 5,
      status_pages: 1,
      projects: 50
    }
  }.freeze

  # Default to free plan if plan is not recognized
  DEFAULT_PLAN = :free

  # ============================================================================
  # QUOTA METHODS - Return the quota limits for each resource type
  # ============================================================================

  def event_quota_value
    quota_for_resource(:events)
  end

  def ai_summaries_quota
    quota_for_resource(:ai_summaries)
  end

  def pull_requests_quota
    quota_for_resource(:pull_requests)
  end

  def uptime_monitors_quota
    quota_for_resource(:uptime_monitors)
  end

  def status_pages_quota
    quota_for_resource(:status_pages)
  end

  def projects_quota
    quota_for_resource(:projects)
  end

  # Human-readable effective plan name, taking trials into account.
  #
  # Example:
  #   account.effective_plan_name # => "Team"
  def effective_plan_name
    effective_plan_key.to_s.titleize
  end

  # ============================================================================
  # USAGE TRACKING METHODS - Return current usage for each resource type
  # Reads from cached columns (updated hourly by UsageSnapshotJob)
  # Returns 0 if cache is empty - view should show "Calculating..." message
  # ============================================================================

  def events_used_in_billing_period
    cached_events_used || 0
  end

  def ai_summaries_used_in_period
    cached_ai_summaries_used || 0
  end

  def pull_requests_used_in_period
    cached_pull_requests_used || 0
  end

  def uptime_monitors_used
    cached_uptime_monitors_used || 0
  end

  def status_pages_used
    cached_status_pages_used || 0
  end

  def projects_used
    cached_projects_used || 0
  end

  # Check if usage data has been cached yet
  def usage_data_available?
    usage_cached_at.present?
  end

  # ============================================================================
  # QUOTA CHECKING METHODS - Check if usage is within quota
  # ============================================================================

  # Check if usage is within quota for a specific resource type
  #
  # @param resource_type [Symbol] :events, :ai_summaries, :pull_requests, :uptime_monitors, :status_pages
  # @return [Boolean] true if within quota, false if exceeded
  #
  # Example:
  #   account.within_quota?(:ai_summaries) # => true
  def within_quota?(resource_type)
    used = usage_for_resource(resource_type)
    quota = quota_for_resource_by_type(resource_type)

    return false unless used && quota
    used < quota
  end

  # Calculate usage percentage for a specific resource type
  #
  # @param resource_type [Symbol] :events, :ai_summaries, :pull_requests, :uptime_monitors, :status_pages
  # @return [Float] percentage used (0.0 - 100.0+)
  #
  # Example:
  #   account.usage_percentage(:pull_requests) # => 45.5
  def usage_percentage(resource_type)
    used = usage_for_resource(resource_type)
    quota = quota_for_resource_by_type(resource_type)

    return 0.0 unless used && quota
    return 0.0 if quota.zero?

    ((used.to_f / quota) * 100).round(2)
  end

  # Get usage summary for all resources
  # Memoized to avoid repeated expensive queries within a request
  #
  # @return [Hash] usage summary with quotas, used, and remaining for all resources
  #
  # Example:
  #   account.usage_summary
  #   # => {
  #   #   events: { quota: 3000, used: 150, remaining: 2850, percentage: 5.0 },
  #   #   ai_summaries: { quota: 5, used: 2, remaining: 3, percentage: 40.0 },
  #   #   ...
  #   # }
  def usage_summary
    @_usage_summary ||= begin
      # Pre-compute plan key once to avoid repeated effective_plan_key calls
      plan_key = effective_plan_key
      plan_quotas = PLAN_QUOTAS[plan_key] || PLAN_QUOTAS[DEFAULT_PLAN]

      %i[events ai_summaries pull_requests uptime_monitors status_pages projects].each_with_object({}) do |resource, hash|
        quota = plan_quotas[resource] || 0
        used = usage_for_resource(resource)

        hash[resource] = {
          quota: quota,
          used: used,
          remaining: [quota - used, 0].max,
          percentage: quota.zero? ? 0.0 : ((used.to_f / quota) * 100).round(2),
          within_quota: used < quota
        }
      end
    end
  end

  private

  # Get quota for a specific resource based on current plan / trial state
  #
  # @param resource_key [Symbol] resource key from PLAN_QUOTAS
  # @return [Integer] quota value
  def quota_for_resource(resource_key)
    plan_key = effective_plan_key
    PLAN_QUOTAS.dig(plan_key, resource_key) || PLAN_QUOTAS.dig(DEFAULT_PLAN, resource_key) || 0
  end

  # Get current usage for a specific resource type
  #
  # @param resource_type [Symbol]
  # @return [Integer] current usage count
  def usage_for_resource(resource_type)
    case resource_type
    when :events
      events_used_in_billing_period
    when :ai_summaries
      ai_summaries_used_in_period
    when :pull_requests
      pull_requests_used_in_period
    when :uptime_monitors
      uptime_monitors_used
    when :status_pages
      status_pages_used
    when :projects
      projects_used
    else
      0
    end
  end

  # Get quota for a specific resource type (alias for consistency)
  #
  # @param resource_type [Symbol]
  # @return [Integer] quota value
  def quota_for_resource_by_type(resource_type)
    case resource_type
    when :events
      event_quota_value
    when :ai_summaries
      ai_summaries_quota
    when :pull_requests
      pull_requests_quota
    when :uptime_monitors
      uptime_monitors_quota
    when :status_pages
      status_pages_quota
    when :projects
      projects_quota
    else
      0
    end
  end

  def effective_plan_key
    # Note: Not memoized because current_plan can change within a request
    # During trial we treat the account as on the Team plan, regardless of
    # what current_plan string is stored. This ensures quotas and messaging
    # match the product behavior: "14‑day Team trial".
    return :team if on_trial?

    # After trial expires without payment method → Free plan
    # (only if they don't have an active subscription)
    # Use respond_to? to safely handle mock objects in tests
    if respond_to?(:trial_expired?) && trial_expired? &&
       respond_to?(:has_payment_method?) && !has_payment_method? &&
       respond_to?(:active_subscription?) && !active_subscription?
      return :free
    end

    normalized_plan_key
  end

  # Normalize the current plan to a symbol key for PLAN_QUOTAS lookup
  #
  # @return [Symbol] :free, :team, or :business
  def normalized_plan_key
    plan = current_plan.to_s.downcase.strip
    plan_sym = plan.to_sym

    PLAN_QUOTAS.key?(plan_sym) ? plan_sym : DEFAULT_PLAN
  end

  # Get billing period start date
  #
  # @return [Time]
  def billing_period_start
    @_billing_period_start ||= event_usage_period_start || Time.current.beginning_of_month
  end

  # Get billing period end date
  #
  # @return [Time]
  def billing_period_end
    @_billing_period_end ||= event_usage_period_end || Time.current.end_of_month
  end
end
