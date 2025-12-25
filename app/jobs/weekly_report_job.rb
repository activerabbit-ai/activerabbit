class WeeklyReportJob
  include Sidekiq::Job

  def perform
    Account.find_each do |account|
      ActsAsTenant.with_tenant(account) do
        report = WeeklyReportBuilder.new(account).build

        account.users.find_each do |user|
          WeeklyReportMailer
            .with(user: user, report: report)
            .weekly_report
            .deliver_later
        end
      end
    end
  end
end
