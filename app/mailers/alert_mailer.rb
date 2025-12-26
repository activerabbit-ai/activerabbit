class AlertMailer < ApplicationMailer
  def send_alert(to:, subject:, body:, project:)
    @body = body
    @project = project
    @project_errors_url = project_errors_url(
      project,
      host: ENV.fetch("APP_HOST", "localhost:3000")
    )
    @project_settings_url = project_settings_url(
      project,
      host: ENV.fetch("APP_HOST", "localhost:3000")
    )

    mail(
      to: to,
      subject: subject,
      template_name: "alert_notification"
    )
  end
end
