# frozen_string_literal: true

# Quota warning helpers for UI messages
module QuotaWarnings
  extend ActiveSupport::Concern

  included do
    # Get warning message for a resource if over quota
    def quota_warning_message(resource_type)
      return nil if within_quota?(resource_type)

      percentage = usage_percentage(resource_type)
      resource_name = resource_type.to_s.humanize

      if percentage >= 100
        over_by = send("#{resource_type}_used") - send("#{resource_type}_quota")
        "⚠️ You've exceeded your #{resource_name} quota by #{over_by}. Please upgrade your plan to continue."
      elsif percentage >= 90
        remaining = send("#{resource_type}_quota") - send("#{resource_type}_used")
        "⚠️ You're running low on #{resource_name}! Only #{remaining} remaining. Consider upgrading soon."
      elsif percentage >= 80
        remaining = send("#{resource_type}_quota") - send("#{resource_type}_used")
        "You've used #{percentage.round}% of your #{resource_name} quota. #{remaining} remaining."
      end
    end

    # Check if should show warning banner
    def show_quota_warning?(resource_type = nil)
      if resource_type
        usage_percentage(resource_type) >= 80
      else
        # Check if any resource is over 80%
        %i[events ai_summaries pull_requests uptime_monitors status_pages projects].any? do |type|
          usage_percentage(type) >= 80
        end
      end
    end

    # Get all resources that need warnings
    def resources_with_warnings
      warnings = []

      %i[events ai_summaries pull_requests uptime_monitors status_pages projects].each do |resource_type|
        if show_quota_warning?(resource_type)
          warnings << {
            resource: resource_type,
            name: resource_type.to_s.humanize,
            percentage: usage_percentage(resource_type),
            used: send("#{resource_type}_used"),
            quota: send("#{resource_type}_quota"),
            remaining: [send("#{resource_type}_quota") - send("#{resource_type}_used"), 0].max,
            level: quota_warning_level(resource_type),
            message: quota_warning_message(resource_type)
          }
        end
      end

      warnings
    end

    # Get warning level (for styling)
    def quota_warning_level(resource_type)
      percentage = usage_percentage(resource_type)

      case percentage
      when 0...80
        :ok
      when 80...90
        :warning
      when 90...100
        :danger
      else
        :exceeded
      end
    end

    # Helper methods for specific resources
    # These delegate to ResourceQuotas concern methods for cleaner code
    # Note: *_quota methods are already defined in ResourceQuotas concern

    def events_used
      events_used_in_billing_period
    end

    def events_quota
      event_quota_value
    end

    def ai_summaries_used
      ai_summaries_used_in_period
    end

    def pull_requests_used
      pull_requests_used_in_period
    end

    def uptime_monitors_used
      super  # Call method from ResourceQuotas
    end

    def status_pages_used
      super  # Call method from ResourceQuotas
    end

    def projects_used
      super  # Call method from ResourceQuotas
    end

    # Check if action should be warned about
    def should_warn_before_action?(resource_type)
      percentage = usage_percentage(resource_type)
      percentage >= 90 # Warn when at 90% or above
    end

    # Check if action should be blocked (optional, not enforced yet)
    def should_block_action?(resource_type)
      return false unless Rails.env.production? # Don't block in dev

      # Could implement hard blocking here in future
      # percentage = usage_percentage(resource_type)
      # percentage >= 110 # Block at 110% overage
      false # Currently no blocking
    end

    # Generate flash message for exceeded quotas
    def quota_exceeded_flash_message
      exceeded = resources_with_warnings.select { |w| w[:level] == :exceeded }
      return nil if exceeded.empty?

      resource_names = exceeded.map { |r| r[:name] }.join(", ")
      "You've exceeded your quota for #{resource_names}. View plan"
    end
  end
end
