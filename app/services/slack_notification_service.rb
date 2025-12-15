class SlackNotificationService
  def initialize(project)
    @project = project
    @token = project.slack_access_token
    @client = Slack::Web::Client.new(token: @token) if @token.present?
  end

  def configured?
    @client.present?
  end

  def send_error_frequency_alert(issue, payload)
    send_message(build_error_frequency_message(issue, payload))
  end

  def send_performance_alert(event, payload)
    send_message(build_performance_message(event, payload))
  end

  def send_n_plus_one_alert(payload)
    send_message(build_n_plus_one_message(payload))
  end

  def send_new_issue_alert(issue)
    send_message(build_new_issue_message(issue))
  end

  private

  def send_message(message)
    return unless configured?

    @client.chat_postMessage(message.merge(
      channel: @project.slack_channel_id || "#active_rabbit_alert",
      username: @project.slack_team_name,
      icon_emoji: ":rabbit:"
    ))
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error "Failed to send Slack message: #{e.message}"
  end

  def project_url
    host = Rails.env.development? ? "http://localhost:3000" : ENV.fetch("APP_HOST", "https://activerabbit.com")
    "#{host}/#{@project.slug}"
  end

  def error_url(issue, tab: nil, event_id: nil)
    q = []
    q << "tab=#{tab}" if tab
    q << "event_id=#{event_id}" if event_id
    query = q.any? ? "?#{q.join('&')}" : ""
    "#{project_url}/errors/#{issue.id}#{query}"
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
              title: "Exception",
              value: issue.exception_class,
              short: false
            },
            {
              title: "Frequency",
              value: "#{payload['count']} occurrences in #{payload['time_window']} minutes",
              short: true
            },
            {
              title: "Location",
              value: issue.controller_action || issue.request_path || "Unknown",
              short: false
            }
          ],
          actions: [
            {
              type: "button",
              text: "Open",
              url: error_url(issue),
              style: "primary"
            },
            {
              type: "button",
              text: "Stack",
              url: error_url(issue, tab: "stack")
            },
            {
              type: "button",
              text: "Samples",
              url: error_url(issue, tab: "samples")
            },
            {
              type: "button",
              text: "Graph",
              url: error_url(issue, tab: "graph")
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
              value: payload["controller_action"] || "Unknown",
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
    incidents = payload["incidents"]
    controller_action = payload["controller_action"]

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
      text: "🆕 *New Issue: #{issue.exception_class}*",
      attachments: [
        {
          color: "danger",
          fallback: "New issue detected: #{issue.exception_class}",
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
              title: "Status",
              value: issue.status.humanize,
              short: true
            },
            {
              title: "Exception",
              value: issue.exception_class,
              short: false
            },
            {
              title: "Location",
              value: issue.controller_action || issue.request_path || "Unknown",
              short: false
            },
            {
              title: "First Seen",
              value: issue.first_seen_at.strftime("%Y-%m-%d %H:%M:%S UTC"),
              short: true
            },
            {
              title: "Occurrences",
              value: issue.count.to_s,
              short: true
            }
          ],
          actions: [
            {
              type: "button",
              text: "Open",
              url: error_url(issue),
              style: "danger"
            },
            {
              type: "button",
              text: "Stack",
              url: error_url(issue, tab: "stack")
            },
            {
              type: "button",
              text: "Samples",
              url: error_url(issue, tab: "samples")
            },
            {
              type: "button",
              text: "Graph",
              url: error_url(issue, tab: "graph")
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
