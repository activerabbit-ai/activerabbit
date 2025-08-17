class AlertMailer < ApplicationMailer
  default from: ENV.fetch('ALERT_FROM_EMAIL', 'alerts@activeagent.com')

  def send_alert(to:, subject:, body:, project:)
    @body = body
    @project = project
    @project_url = admin_root_url(host: ENV.fetch('APP_HOST', 'localhost:3000'))

    mail(
      to: to,
      subject: subject,
      template_name: 'alert_notification'
    )
  end
end
