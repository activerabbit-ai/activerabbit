# frozen_string_literal: true

class UsageSnapshotJob < ApplicationJob
  queue_as :default

  # Calculate and cache usage data for all accounts
  # Runs hourly via Sidekiq Cron to ensure /usage page loads instantly
  #
  # This job pre-computes billing period usage and stores it directly
  # on the accounts table, avoiding expensive COUNT queries on page load.
  def perform
    Rails.logger.info "[UsageSnapshot] Starting usage snapshot for all accounts"

    accounts_updated = 0
    errors = []

    Account.find_each do |account|
      begin
        update_account_usage(account)
        accounts_updated += 1
      rescue => e
        errors << { account_id: account.id, error: e.message }
        Rails.logger.error "[UsageSnapshot] Error updating account #{account.id}: #{e.message}"
      end
    end

    Rails.logger.info "[UsageSnapshot] Completed: #{accounts_updated} accounts updated, #{errors.size} errors"
  end

  private

  def update_account_usage(account)
    # Calculate billing period boundaries
    start_at = account.event_usage_period_start || Time.current.beginning_of_month
    end_at = account.event_usage_period_end || Time.current.end_of_month

    # Use ActsAsTenant.without_tenant to bypass tenant scoping for accurate counts
    ActsAsTenant.without_tenant do
      # Count events (errors) in billing period
      events_count = Event.where(account_id: account.id)
                          .where(occurred_at: start_at..end_at)
                          .count

      # Count performance events in billing period
      performance_events_count = PerformanceEvent.where(account_id: account.id)
                                                 .where(occurred_at: start_at..end_at)
                                                 .count

      # Count AI summaries in billing period
      ai_summaries_count = Issue.where(account_id: account.id)
                                .where(ai_summary_generated_at: start_at..end_at)
                                .count

      # Count pull requests in billing period
      pull_requests_count = AiRequest.where(account_id: account.id, request_type: "pull_request")
                                     .where(occurred_at: start_at..end_at)
                                     .count

      # Count active uptime monitors (current count, not time-based)
      uptime_monitors_count = Healthcheck.where(account_id: account.id, enabled: true).count

      # Count status pages (current count, not time-based)
      status_pages_count = Project.where(account_id: account.id)
                                  .where("settings->>'status_page_enabled' = 'true'")
                                  .count

      # Count projects (current count)
      projects_count = Project.where(account_id: account.id).count

      # Update the account with cached values
      account.update_columns(
        cached_events_used: events_count,
        cached_performance_events_used: performance_events_count,
        cached_ai_summaries_used: ai_summaries_count,
        cached_pull_requests_used: pull_requests_count,
        cached_uptime_monitors_used: uptime_monitors_count,
        cached_status_pages_used: status_pages_count,
        cached_projects_used: projects_count,
        usage_cached_at: Time.current
      )
    end
  end
end
