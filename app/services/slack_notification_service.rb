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

  # Send a message using Slack Block Kit format (for richer messages)
  def send_blocks(blocks:, fallback_text:)
    return unless configured?

    @client.chat_postMessage(
      channel: @project.slack_channel_id || "#active_rabbit_alert",
      username: @project.slack_team_name,
      icon_emoji: ":rabbit:",
      text: fallback_text,
      blocks: blocks
    )
  rescue Slack::Web::Api::Errors::SlackError => e
    Rails.logger.error "Failed to send Slack blocks message: #{e.message}"
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
    # Get the most recent event for additional context
    latest_event = issue.events.order(occurred_at: :desc).first
    context = latest_event&.context || {}
    params = extract_params(context)

    fields = [
      {
        title: "Project",
        value: @project.name,
        short: true
      },
      {
        title: "Environment",
        value: latest_event&.environment || @project.environment || "production",
        short: true
      },
      {
        title: "Exception",
        value: issue.exception_class,
        short: false
      },
      {
        title: "Message",
        value: truncate_text(issue.sample_message || latest_event&.message || "No message", 300),
        short: false
      },
      {
        title: "Frequency",
        value: "#{payload['count']} occurrences in #{payload['time_window']} minutes",
        short: true
      },
      {
        title: "Total",
        value: "#{issue.count} total occurrences",
        short: true
      },
      {
        title: "Location",
        value: issue.controller_action || "Unknown",
        short: true
      },
      {
        title: "Code",
        value: truncate_text(issue.top_frame || "Unknown", 100),
        short: true
      }
    ]

    # Add request paths - show all URLs where the error occurred
    request_paths = payload["request_paths"] || []
    if request_paths.present?
      if request_paths.size == 1
        # Single URL - show as "Latest Request" for consistency
        fields << {
          title: "Request",
          value: truncate_text(request_paths.first, 200),
          short: false
        }
      elsif request_paths.size <= 10
        # Multiple URLs (up to 10) - show all
        paths_text = request_paths.map { |path| "• #{path}" }.join("\n")
        fields << {
          title: "Affected URLs (#{request_paths.size})",
          value: truncate_text(paths_text, 1000),
          short: false
        }
      else
        # Many URLs - show count and first 10 examples
        paths_text = request_paths.first(10).map { |path| "• #{path}" }.join("\n")
        paths_text += "\n... and #{request_paths.size - 10} more"
        fields << {
          title: "Affected URLs (#{request_paths.size})",
          value: truncate_text(paths_text, 1000),
          short: false
        }
      end
    elsif latest_event&.request_path.present?
      # Fallback: if no paths in payload, show latest request
      request_info = latest_event.request_method.present? ?
        "#{latest_event.request_method} #{latest_event.request_path}" :
        latest_event.request_path
      fields << {
        title: "Latest Request",
        value: truncate_text(request_info, 200),
        short: false
      }
    end

    # Add params if available
    if params.present?
      fields << {
        title: "Latest Params",
        value: truncate_text(format_params(params), 200),
        short: false
      }
    end

    {
      text: "🚨 *High Error Frequency Alert*",
      attachments: [
        {
          color: "danger",
          fallback: "High error frequency detected for #{issue.title}",
          fields: fields,
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
    # Get the most recent event for additional context
    latest_event = issue.events.order(occurred_at: :desc).first
    context = latest_event&.context || {}
    params = extract_params(context)

    fields = [
      {
        title: "Project",
        value: @project.name,
        short: true
      },
      {
        title: "Environment",
        value: latest_event&.environment || @project.environment || "production",
        short: true
      },
      {
        title: "Exception",
        value: issue.exception_class,
        short: false
      },
      {
        title: "Message",
        value: truncate_text(issue.sample_message || latest_event&.message || "No message", 300),
        short: false
      },
      {
        title: "Location",
        value: issue.controller_action || "Unknown",
        short: true
      },
      {
        title: "Code",
        value: truncate_text(issue.top_frame || "Unknown", 100),
        short: true
      }
    ]

    # Add request path if available
    if latest_event&.request_path.present?
      request_info = latest_event.request_method.present? ?
        "#{latest_event.request_method} #{latest_event.request_path}" :
        latest_event.request_path
      fields << {
        title: "Request",
        value: truncate_text(request_info, 150),
        short: false
      }
    end

    # Add params if available (useful for debugging RecordNotFound etc)
    if params.present?
      fields << {
        title: "Params",
        value: truncate_text(format_params(params), 200),
        short: false
      }
    end

    # Add occurrence info
    fields << {
      title: "First Seen",
      value: issue.first_seen_at.strftime("%Y-%m-%d %H:%M:%S UTC"),
      short: true
    }
    fields << {
      title: "Occurrences",
      value: issue.count.to_s,
      short: true
    }

    {
      text: "🆕 *New Issue: #{issue.exception_class}*",
      attachments: [
        {
          color: "danger",
          fallback: "New issue detected: #{issue.exception_class} in #{issue.controller_action}",
          fields: fields,
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

  # Extract params from context hash
  def extract_params(context)
    return {} if context.blank?

    # Try different locations where params might be stored
    context.dig("params") ||
      context.dig(:params) ||
      context.dig("request", "params") ||
      context.dig(:request, :params) ||
      {}
  end

  # Format params for display in Slack
  def format_params(params)
    return "" if params.blank?

    # Filter out sensitive and common noise params
    filtered = params.reject do |key, _|
      %w[controller action format authenticity_token utf8 commit password password_confirmation token secret].include?(key.to_s.downcase)
    end

    return "" if filtered.empty?

    # Format as key=value pairs
    filtered.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
  end

  # Truncate text for Slack display
  def truncate_text(text, max_length)
    return "" if text.blank?
    text = text.to_s
    text.length > max_length ? "#{text[0..max_length]}..." : text
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
