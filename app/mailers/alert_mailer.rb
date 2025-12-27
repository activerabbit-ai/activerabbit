class AlertMailer < ApplicationMailer
  def send_alert(to:, subject:, body:, project:, dashboard_url: nil)
    @body = body
    @project = project
    host = ENV.fetch("APP_HOST", "localhost:3000")
    protocol = Rails.env.production? ? "https" : "http"
    @dashboard_url = dashboard_url.presence || project_errors_url(project, host: host, protocol: protocol)
    @project_settings_url = project_settings_url(
      project,
      host: host,
      protocol: protocol
    )

    mail(
      to: to,
      subject: subject,
      template_name: "alert_notification"
    )
  end
end
