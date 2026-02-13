class PerformanceIncidentNotificationJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 3

  URL_HOST = ENV.fetch("APP_HOST", "localhost:3000")
  URL_PROTOCOL = Rails.env.production? ? "https" : "http"

  def perform(incident_id, notification_type)
    incident = nil
    project = nil

    ActsAsTenant.without_tenant do
      incident = PerformanceIncident.find(incident_id)
      project = incident.project
    end

    return unless project.notifications_enabled?

    ActsAsTenant.with_tenant(project.account) do
      case notification_type
      when "open"
        send_open_notification(incident, project)
      when "close"
        send_close_notification(incident, project)
      else
        Rails.logger.error "[PerformanceIncidentNotification] Unknown type: #{notification_type}"
      end
    end

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[PerformanceIncidentNotification] Incident not found: #{incident_id}"
  rescue => e
    Rails.logger.error "[PerformanceIncidentNotification] Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end

  private

  def send_open_notification(incident, project)
    return if incident.open_notification_sent?

    # Send via Slack if configured
    if project.notify_via_slack?
      send_slack_open_notification(incident, project)
    end

    # Send via email if configured
    if project.notify_via_email?
      send_email_open_notification(incident, project)
    end

    incident.update!(open_notification_sent: true)
    Rails.logger.info "[PerformanceIncidentNotification] OPEN notification sent for #{incident.target}"
  end

  def send_close_notification(incident, project)
    return if incident.close_notification_sent?

    # Send via Slack if configured
    if project.notify_via_slack?
      send_slack_close_notification(incident, project)
    end

    # Send via email if configured
    if project.notify_via_email?
      send_email_close_notification(incident, project)
    end

    incident.update!(close_notification_sent: true)
    Rails.logger.info "[PerformanceIncidentNotification] CLOSE notification sent for #{incident.target}"
  end

  def send_slack_open_notification(incident, project)
    emoji = incident.severity == "critical" ? "🔴" : "🟡"
    severity_text = incident.severity == "critical" ? "CRITICAL" : "WARNING"

    blocks = [
      {
        type: "header",
        text: {
          type: "plain_text",
          text: "#{emoji} Performance Incident OPENED",
          emoji: true
        }
      },
      {
        type: "section",
        fields: [
          {
            type: "mrkdwn",
            text: "*Endpoint:*\n`#{incident.target}`"
          },
          {
            type: "mrkdwn",
            text: "*Severity:*\n#{severity_text}"
          },
          {
            type: "mrkdwn",
            text: "*Current p95:*\n#{incident.trigger_p95_ms.round(0)}ms"
          },
          {
            type: "mrkdwn",
            text: "*Threshold:*\n#{incident.threshold_ms.round(0)}ms"
          }
        ]
      },
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*Project:* #{project.name} (#{incident.environment})"
        }
      },
      {
        type: "actions",
        elements: [
          {
            type: "button",
            text: {
              type: "plain_text",
              text: "View Performance Dashboard",
              emoji: true
            },
            url: performance_url(project, incident.target),
            style: "primary"
          }
        ]
      }
    ]

    SlackNotificationService.new(project).send_blocks(
      blocks: blocks,
      fallback_text: "#{emoji} Performance Incident: #{incident.target} - p95 is #{incident.trigger_p95_ms.round(0)}ms (threshold: #{incident.threshold_ms.round(0)}ms)"
    )
  end

  def send_slack_close_notification(incident, project)
    duration = incident.duration_minutes || 0

    blocks = [
      {
        type: "header",
        text: {
          type: "plain_text",
          text: "✅ Performance Incident RESOLVED",
          emoji: true
        }
      },
      {
        type: "section",
        fields: [
          {
            type: "mrkdwn",
            text: "*Endpoint:*\n`#{incident.target}`"
          },
          {
            type: "mrkdwn",
            text: "*Duration:*\n#{duration} minutes"
          },
          {
            type: "mrkdwn",
            text: "*Peak p95:*\n#{incident.peak_p95_ms&.round(0) || 'N/A'}ms"
          },
          {
            type: "mrkdwn",
            text: "*Resolved p95:*\n#{incident.resolve_p95_ms&.round(0) || 'N/A'}ms"
          }
        ]
      },
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*Project:* #{project.name} (#{incident.environment})"
        }
      }
    ]

    SlackNotificationService.new(project).send_blocks(
      blocks: blocks,
      fallback_text: "✅ Performance Incident Resolved: #{incident.target} - recovered after #{duration} minutes (peak: #{incident.peak_p95_ms&.round(0)}ms)"
    )
  end

  def send_email_open_notification(incident, project)
    # Use existing AlertMailer or create dedicated PerformanceIncidentMailer
    AlertMailer.performance_incident_opened(
      project: project,
      incident: incident
    ).deliver_later
  rescue => e
    Rails.logger.error "[PerformanceIncidentNotification] Email error: #{e.message}"
  end

  def send_email_close_notification(incident, project)
    AlertMailer.performance_incident_resolved(
      project: project,
      incident: incident
    ).deliver_later
  rescue => e
    Rails.logger.error "[PerformanceIncidentNotification] Email error: #{e.message}"
  end

  def performance_url(project, target)
    encoded_target = ERB::Util.url_encode(target)
    "#{URL_PROTOCOL}://#{URL_HOST}/#{project.slug}/performance/actions/#{encoded_target}"
  end
end
