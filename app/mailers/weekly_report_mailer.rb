class WeeklyReportMailer < ApplicationMailer
  def weekly_report
    @user = params[:user]
    @account = params[:account]
    @report = params[:report]
    @dashboard_url = dashboard_url(
      host: ENV.fetch("APP_HOST", "localhost:3000")
    )

    period_start = @report[:period].first.strftime("%B %d, %Y")
    period_end = @report[:period].last.strftime("%B %d, %Y")

    mail(
      to: @user.email,
      subject: "Weekly Report for #{@account.name}: #{period_start} - #{period_end}"
    )
  end
end
