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
  # ============================================================================

  def events_used_in_billing_period
    start_at = billing_period_start
    end_at   = billing_period_end

    # Handle ActsAsTenant scoping
    ActsAsTenant.without_tenant do
      Event.where(account_id: id).where(occurred_at: start_at..end_at).count
    end
  end

  def ai_summaries_used_in_period
    start_at = billing_period_start
    end_at   = billing_period_end

    # Handle ActsAsTenant scoping
    ActsAsTenant.without_tenant do
      Issue.where(account_id: id)
           .where(ai_summary_generated_at: start_at..end_at)
           .count
    end
  end

  def pull_requests_used_in_period
    start_at = billing_period_start
    end_at   = billing_period_end

    # Handle ActsAsTenant scoping
    ActsAsTenant.without_tenant do
      AiRequest.where(account_id: id, request_type: "pull_request")
               .where(occurred_at: start_at..end_at)
               .count
    end
  end

  def uptime_monitors_used
    # Handle ActsAsTenant scoping
    ActsAsTenant.without_tenant do
      Healthcheck.where(account_id: id, enabled: true).count
    end
  end

  def status_pages_used
    # Count projects with status pages enabled
    projects.where("settings->>'status_page_enabled' = 'true'").count
  end

  def projects_used
    # Handle ActsAsTenant scoping
    ActsAsTenant.without_tenant do
      Project.where(account_id: id).count
    end
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
    %i[events ai_summaries pull_requests uptime_monitors status_pages projects].each_with_object({}) do |resource, hash|
      quota = quota_for_resource_by_type(resource)
      used = usage_for_resource(resource)

      hash[resource] = {
        quota: quota,
        used: used,
        remaining: [quota - used, 0].max,
        percentage: usage_percentage(resource),
        within_quota: within_quota?(resource)
      }
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
    # During trial we treat the account as on the Team plan, regardless of
    # what current_plan string is stored. This ensures quotas and messaging
    # match the product behavior: "14‑day Team trial".
    return :team if on_trial?
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
    event_usage_period_start || Time.current.beginning_of_month
  end

  # Get billing period end date
  #
  # @return [Time]
  def billing_period_end
    event_usage_period_end || Time.current.end_of_month
  end
end
