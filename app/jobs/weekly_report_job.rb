class WeeklyReportJob
  include Sidekiq::Job

  # Prevent duplicate job execution within the same week
  sidekiq_options lock: :until_executed if respond_to?(:sidekiq_options)

  def perform(account_id = nil)
    week_key = Date.current.beginning_of_week.to_s

    accounts = account_id ? Account.where(id: account_id) : Account.all
    accounts.find_each do |account|
      send_report_for_account(account, week_key)
    end
  end

  private

  def send_report_for_account(account, week_key)
    # Skip if we've already sent reports for this account this week
    cache_key = "weekly_report:#{account.id}:#{week_key}"
    return if Rails.cache.exist?(cache_key)

    # Wrap entire operation in tenant context - needed for mailer template rendering
    # which accesses tenant-scoped Issue objects
    ActsAsTenant.with_tenant(account) do
      report = WeeklyReportBuilder.new(account).build

      # Query users directly to avoid any tenant scoping issues
      users = User.where(account_id: account.id)
      users.find_each.with_index do |user, index|
        # Small delay between emails to avoid Resend rate limit (2/second)
        sleep(0.6) if index > 0

        WeeklyReportMailer
          .with(user: user, account: account, report: report)
          .weekly_report
          .deliver_now
      end
    end

    # Mark this account as having received the report for this week
    # Expires in 7 days to align with weekly schedule
    Rails.cache.write(cache_key, true, expires_in: 7.days)
  end
end
