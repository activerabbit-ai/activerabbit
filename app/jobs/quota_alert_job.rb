# frozen_string_literal: true

class QuotaAlertJob < ApplicationJob
  queue_as :default

  # Check all accounts and send quota alerts where appropriate
  # Runs daily via Sidekiq Cron
  def perform
    Account.find_each do |account|
      check_account_quotas(account)
    end
  end

  private

  def check_account_quotas(account)
    # Initialize alert tracking if needed
    account.last_quota_alert_sent_at ||= {}

    # Check each resource type
    %i[events ai_summaries pull_requests uptime_monitors status_pages].each do |resource_type|
      check_resource_quota(account, resource_type)
    end

    # Save alert timestamps
    account.save! if account.last_quota_alert_sent_at_changed?
  end

  def check_resource_quota(account, resource_type)
    # Wrap in ActsAsTenant.without_tenant to access tenant-scoped models
    percentage = ActsAsTenant.without_tenant do
      account.usage_percentage(resource_type)
    end
    return if percentage < 80 # No alert needed if under 80%

    resource_key = resource_type.to_s
    last_alert_info = account.last_quota_alert_sent_at[resource_key] || {}
    last_sent_at = last_alert_info["sent_at"]&.to_time
    last_level = last_alert_info["level"]

    # Determine alert level
    level = case percentage
    when 80...90 then "80_percent"
    when 90...100 then "90_percent"
    else "exceeded"
    end

    # Check if we should send an alert
    if should_send_alert?(level, last_sent_at, last_level, percentage)
      send_appropriate_alert(account, resource_type, level, last_alert_info)

      # Update last alert info
      account.last_quota_alert_sent_at[resource_key] = {
        "sent_at" => Time.current.iso8601,
        "level" => level,
        "percentage" => percentage.round(2)
      }
    end
  end

  def should_send_alert?(level, last_sent_at, last_level, percentage)
    # Always send if no alert was ever sent
    return true if last_sent_at.nil?

    # If usage has escalated to a higher level, send immediately
    return true if level_escalated?(last_level, level)

    # For exceeded quota, send reminder every 2 days
    if level == "exceeded" && percentage >= 100
      days_since_last = (Time.current - last_sent_at) / 1.day
      return days_since_last >= 2
    end

    # For 80% and 90% warnings, only send once per level
    false
  end

  def level_escalated?(last_level, current_level)
    level_priority = { "80_percent" => 1, "90_percent" => 2, "exceeded" => 3 }
    return false if last_level.nil?

    level_priority[current_level].to_i > level_priority[last_level].to_i
  end

  def send_appropriate_alert(account, resource_type, level, last_alert_info)
    case level
    when "80_percent"
      QuotaAlertMailer.warning_80_percent(account, resource_type).deliver_later
      Rails.logger.info "[QuotaAlert] Sent 80% warning for #{account.name} - #{resource_type}"

    when "90_percent"
      QuotaAlertMailer.warning_90_percent(account, resource_type).deliver_later
      Rails.logger.info "[QuotaAlert] Sent 90% warning for #{account.name} - #{resource_type}"

    when "exceeded"
      # Check if this is first time or a reminder
      first_exceeded_at = last_alert_info["first_exceeded_at"]&.to_time || Time.current
      days_over_quota = ((Time.current - first_exceeded_at) / 1.day).ceil

      if days_over_quota <= 1
        # First time exceeding
        QuotaAlertMailer.quota_exceeded(account, resource_type).deliver_later
        Rails.logger.info "[QuotaAlert] Sent exceeded alert for #{account.name} - #{resource_type}"

        # Track when first exceeded
        account.last_quota_alert_sent_at[resource_type.to_s]["first_exceeded_at"] = Time.current.iso8601
      else
        # Reminder (every 2 days)
        QuotaAlertMailer.quota_exceeded_reminder(account, resource_type, days_over_quota).deliver_later
        Rails.logger.info "[QuotaAlert] Sent exceeded reminder (day #{days_over_quota}) for #{account.name} - #{resource_type}"
      end
    end
  end
end
