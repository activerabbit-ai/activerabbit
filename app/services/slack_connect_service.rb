class SlackConnectService
  def initialize(token)
    @token = token
    @conn = Faraday.new(url: "https://slack.com/api") do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end
  end

  def create_channel(name = "active_rabbit_alert")
    response = @conn.post("conversations.create") do |req|
      req.headers["Authorization"] = "Bearer #{@token}"
      req.headers["Content-Type"] = "application/json"
      req.body = { name: name }.to_json
    end

    data = JSON.parse(response.body)
    if data["ok"]
      channel_id = data["channel"]["id"]
      join_channel(channel_id)
      channel_id
    elsif data["error"] == "name_taken"
      Rails.logger.info "Slack channel '#{name}' already exists, finding it..."
      find_channel(name)
    else
      error_msg = data["error"] || "Unknown error"
      Rails.logger.error "Failed to create Slack channel '#{name}': #{error_msg}"
      nil
    end
  end

  def join_channel(channel_id)
    return unless channel_id

    response = @conn.post("conversations.join") do |req|
      req.headers["Authorization"] = "Bearer #{@token}"
      req.headers["Content-Type"] = "application/json"
      req.body = { channel: channel_id }.to_json
    end

    data = JSON.parse(response.body)
    if !data["ok"] && data["error"] != "already_in_channel"
      Rails.logger.warn "Failed to join Slack channel #{channel_id}: #{data['error'] || 'Unknown error'}"
    end
    data["ok"] || data["error"] == "already_in_channel"
  end

  def find_channel(name)
    cursor = nil

    loop do
      params = { types: "public_channel", limit: 200 }
      params[:cursor] = cursor if cursor

      response = @conn.get("conversations.list", params, { "Authorization" => "Bearer #{@token}" })
      data = JSON.parse(response.body)

      unless data["ok"]
        Rails.logger.error "Failed to list Slack channels: #{data['error'] || 'Unknown error'}"
        return nil
      end

      channel = data["channels"].find { |c| c["name"] == name }
      if channel
        Rails.logger.info "Found existing Slack channel '#{name}' with ID: #{channel['id']}"
        join_channel(channel["id"])
        return channel["id"]
      end

      cursor = data.dig("response_metadata", "next_cursor")
      break if cursor.nil? || cursor.empty?
    end

    Rails.logger.warn "Slack channel '#{name}' not found in workspace"
    nil
  end
end
