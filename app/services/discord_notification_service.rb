class DiscordNotificationService
  include ErrorsHelper

  DISCORD_EMBED_COLOR_DANGER  = 0xED4245 # red
  DISCORD_EMBED_COLOR_WARNING = 0xFEE75C # yellow
  DISCORD_EMBED_COLOR_SUCCESS = 0x57F287 # green
  DISCORD_EMBED_COLOR_INFO    = 0x5865F2 # blurple

  COLOR_MAP = {
    "danger"  => DISCORD_EMBED_COLOR_DANGER,
    "warning" => DISCORD_EMBED_COLOR_WARNING,
    "good"    => DISCORD_EMBED_COLOR_SUCCESS
  }.freeze

  def initialize(project)
    @project = project
    @webhook_url = project.discord_webhook_url
  end

  def configured?
    @webhook_url.present?
  end

  def send_error_frequency_alert(issue, payload)
    embed = build_error_frequency_embed(issue, payload)
    send_webhook(embeds: [embed])
  end

  def send_performance_alert(event, payload)
    embed = build_performance_embed(event, payload)
    send_webhook(embeds: [embed])
  end

  def send_n_plus_one_alert(payload)
    embed = build_n_plus_one_embed(payload)
    send_webhook(embeds: [embed])
  end

  def send_new_issue_alert(issue)
    embed = build_new_issue_embed(issue)
    send_webhook(embeds: [embed])
  end

  def send_custom_alert(title, message, color: "warning")
    embed = build_custom_embed(title, message, color)
    send_webhook(embeds: [embed])
  end

  def send_incident_open(incident)
    embed = build_incident_open_embed(incident)
    send_webhook(embeds: [embed])
  end

  def send_incident_close(incident)
    embed = build_incident_close_embed(incident)
    send_webhook(embeds: [embed])
  end

  private

  def send_webhook(payload)
    return unless configured?

    body = { username: "ActiveRabbit", avatar_url: "https://activerabbit.com/icon.png" }.merge(payload)

    response = Faraday.post(@webhook_url) do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = body.to_json
    end

    unless response.success?
      Rails.logger.error "Discord webhook failed (#{response.status}): #{response.body}"
    end
  rescue StandardError => e
    Rails.logger.error "Failed to send Discord notification: #{e.message}"
  end

  # --- Embed builders ---

  def build_error_frequency_embed(issue, payload)
    latest_event = issue.events.order(occurred_at: :desc).first
    explanation = error_explanation(issue.exception_class)
    message_text = explanation.presence || truncate_text(issue.sample_message || latest_event&.message || "No message", 300)
    env_value = latest_event&.environment || @project.environment || "production"

    fields = [
      { name: "Project",     value: @project.name, inline: true },
      { name: "Frequency",   value: "#{payload['count']} in #{payload['time_window']} min", inline: true },
      { name: "Total",       value: "#{issue.count} occurrences", inline: true },
      { name: "Environment", value: env_value, inline: true },
      { name: "Message",     value: truncate_text(message_text, 1024), inline: false }
    ]

    request_paths = payload["request_paths"] || []
    if request_paths.present?
      paths_text = request_paths.first(5).map { |p| "`#{p}`" }.join("\n")
      paths_text += "\n... and #{request_paths.size - 5} more" if request_paths.size > 5
      fields << { name: "Affected URLs (#{request_paths.size})", value: truncate_text(paths_text, 1024), inline: false }
    elsif latest_event&.request_path.present?
      req = latest_event.request_method.present? ? "#{latest_event.request_method} #{latest_event.request_path}" : latest_event.request_path
      fields << { name: "Latest Request", value: "`#{truncate_text(req, 200)}`", inline: false }
    end

    {
      title: "#{unicode_emoji(:error)} High Error Frequency Alert",
      url: error_url(issue),
      color: DISCORD_EMBED_COLOR_DANGER,
      fields: fields,
      footer: footer,
      timestamp: Time.current.iso8601
    }
  end

  def build_performance_embed(event, payload)
    endpoint = event.target.presence || payload["target"] || payload["controller_action"] || event.request_path || "Unknown"

    {
      title: "#{unicode_emoji(:performance)} Performance Alert",
      url: "#{project_url}/performance",
      color: DISCORD_EMBED_COLOR_WARNING,
      fields: [
        { name: "Project",       value: @project.name, inline: true },
        { name: "Response Time", value: "#{payload['duration_ms']}ms", inline: true },
        { name: "Threshold",     value: "Expected < 2000ms", inline: true },
        { name: "Environment",   value: @project.environment, inline: true },
        { name: "Endpoint",      value: "`#{endpoint}`", inline: false },
        { name: "Occurred",      value: format_time(event.occurred_at), inline: true }
      ],
      footer: footer,
      timestamp: Time.current.iso8601
    }
  end

  def build_n_plus_one_embed(payload)
    incidents = payload["incidents"]
    controller_action = payload["controller_action"]
    query_summary = incidents.first(3).map { |i| "- #{i['count_in_request']}x #{i['sql_fingerprint']['query_type']} queries" }.join("\n")

    {
      title: "#{unicode_emoji(:n_plus_one)} N+1 Query Alert",
      url: "#{project_url}/performance",
      color: DISCORD_EMBED_COLOR_WARNING,
      fields: [
        { name: "Project",          value: @project.name, inline: true },
        { name: "Environment",      value: @project.environment, inline: true },
        { name: "High Severity",    value: incidents.size.to_s, inline: true },
        { name: "Controller/Action", value: "`#{controller_action}`", inline: false },
        { name: "Query Summary",    value: query_summary, inline: false }
      ],
      footer: footer,
      timestamp: Time.current.iso8601
    }
  end

  def build_new_issue_embed(issue)
    latest_event = issue.events.order(occurred_at: :desc).first
    params = extract_params(latest_event&.context || {})
    explanation = error_explanation(issue.exception_class)
    message_text = explanation.presence || truncate_text(issue.sample_message || latest_event&.message || "No message", 300)
    env_value = latest_event&.environment || @project.environment || "production"

    fields = [
      { name: "Project",     value: @project.name, inline: true },
      { name: "First Seen",  value: format_time(issue.first_seen_at), inline: true },
      { name: "Occurrences", value: issue.count.to_s, inline: true },
      { name: "Environment", value: env_value, inline: true },
      { name: "Message",     value: truncate_text(message_text, 1024), inline: false }
    ]

    if latest_event&.request_path.present?
      req = latest_event.request_method.present? ? "#{latest_event.request_method} #{latest_event.request_path}" : latest_event.request_path
      fields << { name: "Request", value: "`#{truncate_text(req, 150)}`", inline: false }
    end

    formatted_params = format_params(params)
    fields << { name: "Params", value: truncate_text(formatted_params, 200), inline: false } if formatted_params.present?

    {
      title: "#{unicode_emoji(:new_issue)} New Issue: #{issue.exception_class}",
      url: error_url(issue),
      color: DISCORD_EMBED_COLOR_DANGER,
      fields: fields,
      footer: footer,
      timestamp: Time.current.iso8601
    }
  end

  def build_custom_embed(title, message, color)
    {
      title: title,
      color: COLOR_MAP[color] || DISCORD_EMBED_COLOR_INFO,
      fields: [
        { name: "Project",     value: @project.name, inline: true },
        { name: "Environment", value: @project.environment, inline: true },
        { name: "Message",     value: message, inline: false }
      ],
      footer: footer,
      timestamp: Time.current.iso8601
    }
  end

  def build_incident_open_embed(incident)
    emoji = incident.severity == "critical" ? "\u{1F534}" : "\u{1F7E1}"
    severity_text = incident.severity == "critical" ? "CRITICAL" : "WARNING"

    {
      title: "#{emoji} Performance Incident OPENED",
      url: performance_url(incident.target),
      color: incident.severity == "critical" ? DISCORD_EMBED_COLOR_DANGER : DISCORD_EMBED_COLOR_WARNING,
      fields: [
        { name: "Endpoint",    value: "`#{incident.target}`", inline: true },
        { name: "Severity",    value: severity_text, inline: true },
        { name: "Current p95", value: "#{incident.trigger_p95_ms.round(0)}ms", inline: true },
        { name: "Threshold",   value: "#{incident.threshold_ms.round(0)}ms", inline: true },
        { name: "Project",     value: "#{@project.name} (#{incident.environment})", inline: false }
      ],
      footer: footer,
      timestamp: Time.current.iso8601
    }
  end

  def build_incident_close_embed(incident)
    duration = incident.duration_minutes || 0

    {
      title: "\u{2705} Performance Incident RESOLVED",
      color: DISCORD_EMBED_COLOR_SUCCESS,
      fields: [
        { name: "Endpoint",     value: "`#{incident.target}`", inline: true },
        { name: "Duration",     value: "#{duration} minutes", inline: true },
        { name: "Peak p95",     value: "#{incident.peak_p95_ms&.round(0) || 'N/A'}ms", inline: true },
        { name: "Resolved p95", value: "#{incident.resolve_p95_ms&.round(0) || 'N/A'}ms", inline: true },
        { name: "Project",      value: "#{@project.name} (#{incident.environment})", inline: false }
      ],
      footer: footer,
      timestamp: Time.current.iso8601
    }
  end

  # --- Helpers ---

  def unicode_emoji(type)
    case type
    when :error       then "\u{1F6A8}"
    when :performance then "\u{26A0}\u{FE0F}"
    when :n_plus_one  then "\u{1F50D}"
    when :new_issue   then "\u{1F195}"
    end
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

  def performance_url(target)
    encoded_target = ERB::Util.url_encode(target)
    "#{project_url}/performance/actions/#{encoded_target}"
  end

  def footer
    { text: "ActiveRabbit", icon_url: "https://activerabbit.com/icon.png" }
  end

  def extract_params(context)
    return {} if context.blank?
    context.dig("params") || context.dig(:params) || context.dig("request", "params") || context.dig(:request, :params) || {}
  end

  def format_params(params)
    return "" if params.blank?
    filtered = params.reject { |key, _| %w[controller action format authenticity_token utf8 commit password password_confirmation token secret].include?(key.to_s.downcase) }
    return "" if filtered.empty?
    filtered.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
  end

  def truncate_text(text, max_length)
    return "" if text.blank?
    text = text.to_s
    text.length > max_length ? "#{text[0..max_length]}..." : text
  end

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
end
