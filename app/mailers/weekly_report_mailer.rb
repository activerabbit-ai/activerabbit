class WeeklyReportMailer < ApplicationMailer
  def weekly_report
    @user = params[:user]
    @account = params[:account]
    @report = params[:report]
    host = ENV.fetch("APP_HOST", "localhost:3000")
    @dashboard_url = dashboard_url(host: host)
    @errors_url = errors_url(host: host)
    @performance_url = performance_url(host: host)

    if @report[:performance].any?
      project_ids = @report[:performance].map(&:project_id).compact.uniq
      @performance_projects = @account.projects.where(id: project_ids).index_by(&:id) if project_ids.any?
    end

    period_start = @report[:period].first.strftime("%B %d, %Y")
    period_end = @report[:period].last.strftime("%B %d, %Y")

    mail(
      to: @user.email,
      subject: "Weekly Report for #{@account.name}: #{period_start} - #{period_end}"
    )
  end
end
