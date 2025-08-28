class SlackNotificationService
  include Rails.application.routes.url_helpers

  def initialize(project)
    @project = project
    @webhook_url = project.settings&.dig('slack_webhook_url')
  end

  def configured?
    @webhook_url.present?
  end

  def send_error_frequency_alert(issue, payload)
    return unless configured?

    message = build_error_frequency_message(issue, payload)
    send_notification(message)
  end

  def send_performance_alert(event, payload)
    return unless configured?

    message = build_performance_message(event, payload)
    send_notification(message)
  end

  def send_n_plus_one_alert(payload)
    return unless configured?

    message = build_n_plus_one_message(payload)
    send_notification(message)
  end

  def send_new_issue_alert(issue)
    return unless configured?

    message = build_new_issue_message(issue)
    send_notification(message)
  end

  def send_custom_alert(title, message, color: 'warning')
    return unless configured?

    notification = build_custom_message(title, message, color)
    send_notification(notification)
  end

  private

  def send_notification(message)
    notifier = Slack::Notifier.new(@webhook_url) do
      defaults channel: slack_channel,
               username: 'ActiveRabbit',
               icon_emoji: ':rabbit:'
    end

    notifier.post(message)
  rescue StandardError => e
    Rails.logger.error "Failed to send Slack notification: #{e.message}"
    raise e
  end

  def slack_channel
    @project.settings&.dig('slack_channel') || '#alerts'
  end

  def project_url
    if Rails.env.development?
      "http://localhost:3000/projects/#{@project.slug}"
    else
      "#{ENV.fetch('APP_HOST', 'https://activerabbit.com')}/projects/#{@project.slug}"
    end
  end

  def build_error_frequency_message(issue, payload)
    {
      text: "🚨 *High Error Frequency Alert*",
      attachments: [
        {
          color: "danger",
          fallback: "High error frequency detected for #{issue.title}",
          fields: [
            {
              title: "Project",
              value: @project.name,
              short: true
            },
            {
              title: "Environment",
              value: @project.environment,
              short: true
            },
            {
              title: "Issue",
              value: issue.title.truncate(100),
              short: false
            },
            {
              title: "Frequency",
              value: "#{payload['count']} occurrences in #{payload['time_window']} minutes",
              short: true
            },
            {
              title: "Exception Type",
              value: issue.exception_type,
              short: true
            },
            {
              title: "Location",
              value: issue.controller_action || issue.request_path || 'Unknown',
              short: false
            }
          ],
          actions: [
            {
              type: "button",
              text: "View Issue",
              url: "#{project_url}/errors/#{issue.id}",
              style: "primary"
            }
          ],
          footer: "ActiveRabbit Error Tracking",
          footer_icon: "https://activerabbit.com/icon.png",
          ts: Time.current.to_i
        }
      ]
    }
  end

  def build_performance_message(event, payload)
    {
      text: "⚠️ *Performance Alert*",
      attachments: [
        {
          color: "warning",
          fallback: "Slow response time detected: #{payload['duration_ms']}ms",
          fields: [
            {
              title: "Project",
              value: @project.name,
              short: true
            },
            {
              title: "Environment",
              value: @project.environment,
              short: true
            },
            {
              title: "Response Time",
              value: "#{payload['duration_ms']}ms",
              short: true
            },
            {
              title: "Threshold",
              value: "Expected < 2000ms",
              short: true
            },
            {
              title: "Endpoint",
              value: payload['controller_action'] || 'Unknown',
              short: false
            },
            {
              title: "Occurred At",
              value: event.occurred_at.strftime("%Y-%m-%d %H:%M:%S UTC"),
              short: true
            }
          ],
          actions: [
            {
              type: "button",
              text: "View Performance",
              url: "#{project_url}/performance",
              style: "primary"
            }
          ],
          footer: "ActiveRabbit Performance Monitoring",
          footer_icon: "https://activerabbit.com/icon.png",
          ts: Time.current.to_i
        }
      ]
    }
  end

  def build_n_plus_one_message(payload)
    incidents = payload['incidents']
    controller_action = payload['controller_action']

    query_summary = incidents.first(3).map do |incident|
      "• #{incident['count_in_request']}x #{incident['sql_fingerprint']['query_type']} queries"
    end.join("\n")

    {
      text: "🔍 *N+1 Query Alert*",
      attachments: [
        {
          color: "warning",
          fallback: "N+1 queries detected in #{controller_action}",
          fields: [
            {
              title: "Project",
              value: @project.name,
              short: true
            },
            {
              title: "Environment",
              value: @project.environment,
              short: true
            },
            {
              title: "Controller/Action",
              value: controller_action,
              short: false
            },
            {
              title: "High Severity Incidents",
              value: incidents.size.to_s,
              short: true
            },
            {
              title: "Impact",
              value: "Database performance degradation",
              short: true
            },
            {
              title: "Query Summary",
              value: query_summary,
              short: false
            }
          ],
          actions: [
            {
              type: "button",
              text: "View Queries",
              url: "#{project_url}/performance",
              style: "primary"
            }
          ],
          footer: "ActiveRabbit Query Analysis",
          footer_icon: "https://activerabbit.com/icon.png",
          ts: Time.current.to_i
        }
      ]
    }
  end

  def build_new_issue_message(issue)
    {
      text: "🆕 *New Issue Detected*",
      attachments: [
        {
          color: "danger",
          fallback: "New issue detected: #{issue.exception_type}",
          fields: [
            {
              title: "Project",
              value: @project.name,
              short: true
            },
            {
              title: "Environment",
              value: @project.environment,
              short: true
            },
            {
              title: "Exception Type",
              value: issue.exception_type,
              short: true
            },
            {
              title: "Status",
              value: issue.status.humanize,
              short: true
            },
            {
              title: "Error Message",
              value: issue.message.truncate(200),
              short: false
            },
            {
              title: "Location",
              value: issue.controller_action || issue.request_path || 'Unknown',
              short: false
            },
            {
              title: "First Seen",
              value: issue.first_seen_at.strftime("%Y-%m-%d %H:%M:%S UTC"),
              short: true
            }
          ],
          actions: [
            {
              type: "button",
              text: "Investigate Issue",
              url: "#{project_url}/errors/#{issue.id}",
              style: "danger"
            },
            {
              type: "button",
              text: "Mark as WIP",
              url: "#{project_url}/errors/#{issue.id}/edit",
              style: "primary"
            }
          ],
          footer: "ActiveRabbit Error Tracking",
          footer_icon: "https://activerabbit.com/icon.png",
          ts: Time.current.to_i
        }
      ]
    }
  end

  def build_custom_message(title, message, color)
    {
      text: title,
      attachments: [
        {
          color: color,
          fallback: "#{title}: #{message}",
          fields: [
            {
              title: "Project",
              value: @project.name,
              short: true
            },
            {
              title: "Environment",
              value: @project.environment,
              short: true
            },
            {
              title: "Message",
              value: message,
              short: false
            }
          ],
          footer: "ActiveRabbit",
          footer_icon: "https://activerabbit.com/icon.png",
          ts: Time.current.to_i
        }
      ]
    }
  end
end
