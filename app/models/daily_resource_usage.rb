class DailyResourceUsage < ApplicationRecord
  belongs_to :account

  validates :day, presence: true, uniqueness: { scope: :account_id }

  # Class methods
  class << self
    # Aggregate usage data for a specific account and day
    # We need ActsAsTenant.without_tenant because we're querying tenant-scoped models
    # (Event, Issue, AiRequest, Healthcheck, Project) with explicit account_id
    def aggregate_for_account_and_day(account_id, day = Date.current)
      ActsAsTenant.without_tenant do
        usage = find_or_initialize_by(account_id: account_id, day: day)

        # Count errors (events) for the day (null if zero)
        errors = Event.where(account_id: account_id)
                      .where("DATE(occurred_at) = ?", day)
                      .count
        usage.errors_count = errors > 0 ? errors : nil

        # Count AI summaries generated for the day (null if zero)
        ai_summaries = Issue.where(account_id: account_id)
                            .where("DATE(ai_summary_generated_at) = ?", day)
                            .count
        usage.ai_summaries_count = ai_summaries > 0 ? ai_summaries : nil

        # Count pull requests created for the day (null if zero)
        prs = AiRequest.where(account_id: account_id, request_type: "pull_request")
                       .where("DATE(occurred_at) = ?", day)
                       .count
        usage.pull_requests_count = prs > 0 ? prs : nil

        # Count active uptime monitors for the account (null if zero)
        monitors = Healthcheck.where(account_id: account_id, enabled: true).count
        usage.uptime_monitors_count = monitors > 0 ? monitors : nil

        # Count status pages (null if zero)
        status_pages = Project.where(account_id: account_id)
                              .where("settings->>'status_page_enabled' = 'true'")
                              .count
        usage.status_pages_count = status_pages > 0 ? status_pages : nil

        usage.save!
        usage
      end
    end

    # Get aggregated usage for a specific billing period
    def usage_for_period(account_id, start_date, end_date)
      where(account_id: account_id, day: start_date..end_date)
        .select(
          "COALESCE(SUM(errors_count), 0) as total_errors",
          "COALESCE(SUM(ai_summaries_count), 0) as total_ai_summaries",
          "COALESCE(SUM(pull_requests_count), 0) as total_pull_requests",
          "COALESCE(MAX(uptime_monitors_count), 0) as max_uptime_monitors",
          "COALESCE(MAX(status_pages_count), 0) as max_status_pages"
        )
        .first
    end
  end

  # Instance methods
  def total_resources_used
    errors_count.to_i + ai_summaries_count.to_i + pull_requests_count.to_i +
      uptime_monitors_count.to_i + status_pages_count.to_i
  end
end
