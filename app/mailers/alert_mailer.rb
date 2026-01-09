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

  # Performance Incident OPENED notification
  def performance_incident_opened(project:, incident:)
    @project = project
    @incident = incident
    @host = ENV.fetch("APP_HOST", "localhost:3000")
    @protocol = Rails.env.production? ? "https" : "http"

    severity_emoji = incident.severity == "critical" ? "🔴" : "🟡"
    severity_text = incident.severity.upcase

    @subject = "#{severity_emoji} [#{severity_text}] Performance degraded: #{incident.target}"
    @body = <<~BODY
      Performance incident detected for #{project.name}

      Endpoint: #{incident.target}
      Severity: #{severity_text}
      Current p95: #{incident.trigger_p95_ms.round(0)}ms
      Threshold: #{incident.threshold_ms.round(0)}ms
      Environment: #{incident.environment}

      The p95 latency for this endpoint has exceeded the threshold for #{PerformanceIncident::DEFAULT_WARMUP_COUNT} consecutive minutes.
    BODY

    @dashboard_url = "#{@protocol}://#{@host}/#{project.slug}/performance"

    recipients = project_notification_recipients(project)
    return if recipients.empty?

    mail(
      to: recipients,
      subject: @subject,
      template_name: "performance_incident"
    )
  end

  # Performance Incident RESOLVED notification
  def performance_incident_resolved(project:, incident:)
    @project = project
    @incident = incident
    @host = ENV.fetch("APP_HOST", "localhost:3000")
    @protocol = Rails.env.production? ? "https" : "http"

    duration = incident.duration_minutes || 0

    @subject = "✅ Performance recovered: #{incident.target}"
    @body = <<~BODY
      Performance incident resolved for #{project.name}

      Endpoint: #{incident.target}
      Duration: #{duration} minutes
      Peak p95: #{incident.peak_p95_ms&.round(0) || 'N/A'}ms
      Resolved p95: #{incident.resolve_p95_ms&.round(0) || 'N/A'}ms
      Environment: #{incident.environment}

      The p95 latency has returned to normal levels.
    BODY

    @dashboard_url = "#{@protocol}://#{@host}/#{project.slug}/performance"

    recipients = project_notification_recipients(project)
    return if recipients.empty?

    mail(
      to: recipients,
      subject: @subject,
      template_name: "performance_incident"
    )
  end

  private

  def project_notification_recipients(project)
    # Get email recipients for the project
    # Could be from project settings, account admins, or user
    recipients = []

    # Add project owner
    recipients << project.user.email if project.user&.email.present?

    # Add account admin emails if configured
    if project.account&.respond_to?(:admin_emails)
      recipients += Array(project.account.admin_emails)
    end

    # Check project settings for additional recipients
    notification_emails = project.settings&.dig("notifications", "emails")
    recipients += Array(notification_emails) if notification_emails.present?

    recipients.uniq.compact
  end
end
