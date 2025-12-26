class WeeklyReportMailer < ApplicationMailer
  def weekly_report
    @user = params[:user]
    @report = params[:report]
    @dashboard_url = dashboard_url(
      host: ENV.fetch("APP_HOST", "localhost:3000")
    )

    mail(
      to: @user.email,
      subject: "Your weekly system report"
    )
  end
end
