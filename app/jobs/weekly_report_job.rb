class WeeklyReportJob
  include Sidekiq::Job

  def perform
    Account.find_each do |account|
      ActsAsTenant.with_tenant(account) do
        report = WeeklyReportBuilder.new(account).build

        account.users.find_each.with_index do |user, index|
          WeeklyReportMailer
            .with(user: user, account: account, report: report)
            .weekly_report
            .deliver_later(wait: index.seconds)
        end
      end
    end
  end
end
