class WeeklyReportJob
  include Sidekiq::Job

  def perform
    Account.find_each do |account|
      ActsAsTenant.with_tenant(account) do
        report = WeeklyReportBuilder.new(account).build

        account.users.find_each.with_index do |user, index|
          # Small delay between emails to avoid Resend rate limit (2/second)
          sleep(0.6) if index > 0

          WeeklyReportMailer
            .with(user: user, account: account, report: report)
            .weekly_report
            .deliver_now
        end
      end
    end
  end
end
