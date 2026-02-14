class SlackNotificationService
  include ErrorsHelper

  def initialize(project)
    @project = project
    @token = project.slack_access_token
    @client = Slack::Web::Client.new(token: @token) if @token.present?
  end

  def configured?
    return false unless @client.present?
    # Free plan does not include Slack notifications
    return false if @project&.account && !@project.account.slack_notifications_allowed?
    true
  end

  def send_error_frequency_alert(issue, payload)
    blocks, fallback = build_error_frequency_blocks(issue, payload)
    send_blocks(blocks: blocks, fallback_text: fallback)
  end

  def send_performance_alert(event, payload)
    blocks, fallback = build_performance_blocks(event, payload)
    send_blocks(blocks: blocks, fallback_text: fallback)
  end

  def send_n_plus_one_alert(payload)
    blocks, fallback = build_n_plus_one_blocks(payload)
    send_blocks(blocks: blocks, fallback_text: fallback)
  end

  def send_new_issue_alert(issue)
    blocks, fallback = build_new_issue_blocks(issue)
    send_blocks(blocks: blocks, fallback_text: fallback)
  end

  def send_custom_alert(title, message, color: "warning")
    blocks, fallback = build_custom_blocks(title, message, color)
    send_blocks(blocks: blocks, fallback_text: fallback)
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

  # --- Block Kit builders (type: "actions" so buttons display in Slack) ---

  def build_error_frequency_blocks(issue, payload)
    latest_event = issue.events.order(occurred_at: :desc).first
    explanation = error_explanation(issue.exception_class)
    message_text = explanation.presence || truncate_text(issue.sample_message || latest_event&.message || "No message", 300)
    request_paths = payload["request_paths"] || []
    env_value = latest_event&.environment || @project.environment || "production"

    blocks = [
      { type: "header", text: { type: "plain_text", text: "🚨 High Error Frequency Alert", emoji: true } },
      {
        type: "section",
        fields: [
          { type: "mrkdwn", text: "*Project:*\n#{@project.name}" },
          { type: "mrkdwn", text: "*Frequency:*\n#{payload['count']} in #{payload['time_window']} min" },
          { type: "mrkdwn", text: "*Total:*\n#{issue.count} occurrences" },
          { type: "mrkdwn", text: "*Environment:*\n#{env_value}" }
        ]
      },
      { type: "section", text: { type: "mrkdwn", text: "*Message:*\n#{message_text}" } }
    ]
    if request_paths.present?
      if request_paths.size == 1
        blocks << { type: "section", text: { type: "mrkdwn", text: "*Request:*\n#{truncate_text(request_paths.first, 200)}" } }
      else
        paths_text = request_paths.size <= 10 ? request_paths.map { |p| "• #{p}" }.join("\n") : request_paths.first(10).map { |p| "• #{p}" }.join("\n") + "\n... and #{request_paths.size - 10} more"
        blocks << { type: "section", text: { type: "mrkdwn", text: "*Affected URLs (#{request_paths.size}):*\n#{truncate_text(paths_text, 1000)}" } }
      end
    elsif latest_event&.request_path.present?
      req = latest_event.request_method.present? ? "#{latest_event.request_method} #{latest_event.request_path}" : latest_event.request_path
      blocks << { type: "section", text: { type: "mrkdwn", text: "*Latest Request:*\n#{truncate_text(req, 200)}" } }
    end
    blocks << {
      type: "actions",
      elements: [
        { type: "button", text: { type: "plain_text", text: "Open", emoji: true }, url: error_url(issue), style: "primary" },
        { type: "button", text: { type: "plain_text", text: "Stack", emoji: true }, url: error_url(issue, tab: "stack") },
        { type: "button", text: { type: "plain_text", text: "Samples", emoji: true }, url: error_url(issue, tab: "samples") },
        { type: "button", text: { type: "plain_text", text: "Graph", emoji: true }, url: error_url(issue, tab: "graph") }
      ]
    }
    [blocks, "High error frequency: #{issue.title}"]
  end

  def build_performance_blocks(event, payload)
    endpoint = event.target.presence || payload["target"] || payload["controller_action"] || event.request_path || "Unknown"
    blocks = [
      { type: "header", text: { type: "plain_text", text: "⚠️ Performance Alert", emoji: true } },
      {
        type: "section",
        fields: [
          { type: "mrkdwn", text: "*Project:*\n#{@project.name}" },
          { type: "mrkdwn", text: "*Response Time:*\n#{payload['duration_ms']}ms" },
          { type: "mrkdwn", text: "*Threshold:*\nExpected < 2000ms" },
          { type: "mrkdwn", text: "*Environment:*\n#{@project.environment}" }
        ]
      },
      { type: "section", text: { type: "mrkdwn", text: "*Endpoint:*\n#{endpoint}" } },
      { type: "section", text: { type: "mrkdwn", text: "*Occurred:* #{format_time(event.occurred_at)}" } },
      {
        type: "actions",
        elements: [
          { type: "button", text: { type: "plain_text", text: "View Performance", emoji: true }, url: "#{project_url}/performance", style: "primary" }
        ]
      }
    ]
    [blocks, "Performance alert: #{payload['duration_ms']}ms - #{endpoint}"]
  end

  def build_n_plus_one_blocks(payload)
    incidents = payload["incidents"]
    controller_action = payload["controller_action"]
    query_summary = incidents.first(3).map { |i| "• #{i['count_in_request']}x #{i['sql_fingerprint']['query_type']} queries" }.join("\n")
    blocks = [
      { type: "header", text: { type: "plain_text", text: "🔍 N+1 Query Alert", emoji: true } },
      {
        type: "section",
        fields: [
          { type: "mrkdwn", text: "*Project:*\n#{@project.name}" },
          { type: "mrkdwn", text: "*Environment:*\n#{@project.environment}" },
          { type: "mrkdwn", text: "*High Severity:*\n#{incidents.size}" },
          { type: "mrkdwn", text: "*Impact:*\nDB performance" }
        ]
      },
      { type: "section", text: { type: "mrkdwn", text: "*Controller/Action:*\n#{controller_action}" } },
      { type: "section", text: { type: "mrkdwn", text: "*Query summary:*\n#{query_summary}" } },
      {
        type: "actions",
        elements: [
          { type: "button", text: { type: "plain_text", text: "View Queries", emoji: true }, url: "#{project_url}/performance", style: "primary" }
        ]
      }
    ]
    [blocks, "N+1 detected in #{controller_action}"]
  end

  def build_new_issue_blocks(issue)
    latest_event = issue.events.order(occurred_at: :desc).first
    params = extract_params(latest_event&.context || {})
    explanation = error_explanation(issue.exception_class)
    message_text = explanation.presence || truncate_text(issue.sample_message || latest_event&.message || "No message", 300)
    env_value = latest_event&.environment || @project.environment || "production"

    blocks = [
      { type: "header", text: { type: "plain_text", text: "🆕 New Issue: #{issue.exception_class}", emoji: true } },
      {
        type: "section",
        fields: [
          { type: "mrkdwn", text: "*Project:*\n#{@project.name}" },
          { type: "mrkdwn", text: "*First Seen:*\n#{format_time(issue.first_seen_at)}" },
          { type: "mrkdwn", text: "*Occurrences:*\n#{issue.count}" },
          { type: "mrkdwn", text: "*Environment:*\n#{env_value}" }
        ]
      },
      { type: "section", text: { type: "mrkdwn", text: "*Message:*\n#{message_text}" } }
    ]
    if latest_event&.request_path.present?
      req = latest_event.request_method.present? ? "#{latest_event.request_method} #{latest_event.request_path}" : latest_event.request_path
      blocks << { type: "section", text: { type: "mrkdwn", text: "*Request:*\n#{truncate_text(req, 150)}" } }
    end
    formatted_params = format_params(params)
    blocks << { type: "section", text: { type: "mrkdwn", text: "*Params:*\n#{truncate_text(formatted_params, 200)}" } } if formatted_params.present?
    blocks << {
      type: "actions",
      elements: [
        { type: "button", text: { type: "plain_text", text: "Open", emoji: true }, url: error_url(issue), style: "danger" },
        { type: "button", text: { type: "plain_text", text: "Stack", emoji: true }, url: error_url(issue, tab: "stack") },
        { type: "button", text: { type: "plain_text", text: "Samples", emoji: true }, url: error_url(issue, tab: "samples") },
        { type: "button", text: { type: "plain_text", text: "Graph", emoji: true }, url: error_url(issue, tab: "graph") }
      ]
    }
    [blocks, "New issue: #{issue.exception_class}"]
  end

  def build_custom_blocks(title, message, color)
    blocks = [
      { type: "header", text: { type: "plain_text", text: title, emoji: true } },
      {
        type: "section",
        fields: [
          { type: "mrkdwn", text: "*Project:*\n#{@project.name}" },
          { type: "mrkdwn", text: "*Environment:*\n#{@project.environment}" }
        ]
      },
      { type: "section", text: { type: "mrkdwn", text: "*Message:*\n#{message}" } },
      {
        type: "actions",
        elements: [
          { type: "button", text: { type: "plain_text", text: "Open Project", emoji: true }, url: project_url, style: "primary" }
        ]
      }
    ]
    [blocks, "#{title}: #{message}"]
  end

  def build_error_frequency_message(issue, payload)
    latest_event = issue.events.order(occurred_at: :desc).first

    # Get human-readable explanation for this error type
    explanation = error_explanation(issue.exception_class)
    message_text = explanation.presence || truncate_text(issue.sample_message || latest_event&.message || "No message", 300)

    fields = [
      {
        title: "Project",
        value: @project.name,
        short: true
      },
      {
        title: "Message",
        value: message_text,
        short: false
      },
      {
        title: "Frequency",
        value: "#{payload['count']} occurrences in #{payload['time_window']} minutes",
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

    # Add Total and Environment at the bottom
    fields << {
      title: "Total",
      value: "#{issue.count} total occurrences",
      short: true
    }
    fields << {
      title: "Environment",
      value: latest_event&.environment || @project.environment || "production",
      short: true
    }

    {
      text: "🚨 *High Error Frequency Alert*",
      attachments: [
        {
          color: "danger",
          fallback: "High error frequency detected for #{issue.title}",
          fields: fields,
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
              title: "Endpoint",
              value: event.target.presence || payload["target"] || payload["controller_action"] || event.request_path || "Unknown",
              short: false
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
              title: "Occurred At",
              value: format_time(event.occurred_at),
              short: true
            },
            {
              title: "Environment",
              value: @project.environment,
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

    # Get human-readable explanation for this error type
    explanation = error_explanation(issue.exception_class)
    message_text = explanation.presence || truncate_text(issue.sample_message || latest_event&.message || "No message", 300)

    fields = [
      {
        title: "Project",
        value: @project.name,
        short: true
      },
      {
        title: "Message",
        value: message_text,
        short: false
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
    formatted_params = format_params(params)
    if formatted_params.present?
      fields << {
        title: "Params",
        value: truncate_text(formatted_params, 200),
        short: false
      }
    end

    # Add occurrence info
    fields << {
      title: "First Seen",
      value: format_time(issue.first_seen_at),
      short: false
    }
    fields << {
      title: "Occurrences",
      value: issue.count.to_s,
      short: false
    }
    fields << {
      title: "Environment",
      value: latest_event&.environment || @project.environment || "production",
      short: true
    }

    {
      text: "🆕 *New Issue: #{issue.exception_class}*",
      attachments: [
        {
          color: "danger",
          fallback: "New issue detected: #{issue.exception_class} in #{issue.controller_action}",
          fields: fields,
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

  # Format time in human-readable format
  def format_time(time)
    return "Unknown" if time.blank?

    time = time.utc
    today = Time.current.utc.to_date

    if time.to_date == today
      "Today at #{time.strftime('%H:%M UTC')}"
    elsif time.to_date == today - 1.day
      "Yesterday at #{time.strftime('%H:%M UTC')}"
    elsif time.year == today.year
      time.strftime("%b %d at %H:%M UTC")
    else
      time.strftime("%b %d, %Y at %H:%M UTC")
    end
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
