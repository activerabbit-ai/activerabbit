# frozen_string_literal: true

class QuotaAlertMailer < ApplicationMailer
  default from: "alerts@activerabbit.ai"

  # Send alert when user reaches 80% of quota
  def warning_80_percent(account, resource_type)
    @account = account
    @resource_type = resource_type
    @resource_name = resource_type.to_s.humanize
    @quota = quota_for_resource(resource_type)
    @used = usage_for_resource(resource_type)
    @remaining = [@quota - @used, 0].max
    @percentage = @account.usage_percentage(resource_type)
    @upgrade_url = pricing_url

    @primary_user = @account.users.first

    mail(
      to: @primary_user.email,
      subject: "⚠️ #{@resource_name} Usage at #{@percentage.round}%"
    )
  end

  # Send alert when user reaches 90% of quota
  def warning_90_percent(account, resource_type)
    @account = account
    @resource_type = resource_type
    @resource_name = resource_type.to_s.humanize
    @quota = quota_for_resource(resource_type)
    @used = usage_for_resource(resource_type)
    @remaining = [@quota - @used, 0].max
    @percentage = @account.usage_percentage(resource_type)
    @upgrade_url = pricing_url

    @primary_user = @account.users.first

    mail(
      to: @primary_user.email,
      subject: "🚨 #{@resource_name} Usage at #{@percentage.round}% - Upgrade Recommended"
    )
  end

  # Send alert when user reaches 100% of quota
  def quota_exceeded(account, resource_type)
    @account = account
    @resource_type = resource_type
    @resource_name = resource_type.to_s.humanize
    @quota = quota_for_resource(resource_type)
    @used = usage_for_resource(resource_type)
    @over_by = @used - @quota
    @percentage = @account.usage_percentage(resource_type)
    @upgrade_url = pricing_url

    @primary_user = @account.users.first

    mail(
      to: @primary_user.email,
      subject: "❌ #{@resource_name} Quota Exceeded - Please Upgrade"
    )
  end

  # Send reminder every 2 days until plan is upgraded
  def quota_exceeded_reminder(account, resource_type, days_over_quota)
    @account = account
    @resource_type = resource_type
    @resource_name = resource_type.to_s.humanize
    @quota = quota_for_resource(resource_type)
    @used = usage_for_resource(resource_type)
    @over_by = @used - @quota
    @percentage = @account.usage_percentage(resource_type)
    @days_over_quota = days_over_quota
    @upgrade_url = pricing_url

    @primary_user = @account.users.first

    mail(
      to: @primary_user.email,
      subject: "🔴 Reminder: #{@resource_name} Quota Exceeded (Day #{@days_over_quota})"
    )
  end

  private

  def quota_for_resource(resource_type)
    case resource_type
    when :events
      @account.event_quota_value
    when :ai_summaries
      @account.ai_summaries_quota
    when :pull_requests
      @account.pull_requests_quota
    when :uptime_monitors
      @account.uptime_monitors_quota
    when :status_pages
      @account.status_pages_quota
    else
      0
    end
  end

  def usage_for_resource(resource_type)
    case resource_type
    when :events
      @account.events_used_in_billing_period
    when :ai_summaries
      @account.ai_summaries_used_in_period
    when :pull_requests
      @account.pull_requests_used_in_period
    when :uptime_monitors
      @account.uptime_monitors_used
    when :status_pages
      @account.status_pages_used
    else
      0
    end
  end

  def pricing_url
    Rails.application.routes.url_helpers.pricing_url(
      host: ENV.fetch("APP_HOST", "localhost:3000"),
      protocol: Rails.env.production? ? "https" : "http"
    )
  end
end

