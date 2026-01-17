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
      data["channel"]["id"]
    else
      error_msg = data["error"] || "Unknown error"
      Rails.logger.warn "Failed to create Slack channel '#{name}': #{error_msg}. Attempting to find existing channel..."
      find_channel(name)
    end
  end

  def find_channel(name)
    response = @conn.get("conversations.list", { types: "public_channel,private_channel" }, { "Authorization" => "Bearer #{@token}" })
    data = JSON.parse(response.body)
    unless data["ok"]
      Rails.logger.error "Failed to list Slack channels: #{data['error'] || 'Unknown error'}"
      return nil
    end
    channel = data["channels"].find { |c| c["name"] == name }
    if channel
      Rails.logger.info "Found existing Slack channel '#{name}' with ID: #{channel['id']}"
      channel["id"]
    else
      Rails.logger.warn "Slack channel '#{name}' not found in workspace"
      nil
    end
  end
end
