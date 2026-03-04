class DiscordAuthController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project, only: [:authorize]

  def authorize
    client_id = ENV["DISCORD_CLIENT_ID"]

    state = SecureRandom.hex(32)
    session[:discord_oauth_state] = state
    session[:discord_project_id] = @project.id

    discord_url = "https://discord.com/oauth2/authorize" \
                  "?client_id=#{client_id}" \
                  "&redirect_uri=#{ERB::Util.url_encode(callback_url)}" \
                  "&response_type=code" \
                  "&scope=webhook.incoming" \
                  "&state=#{state}"

    redirect_to discord_url, allow_other_host: true
  end

  def callback
    unless params[:state] == session.delete(:discord_oauth_state)
      Rails.logger.warn "Invalid Discord OAuth state"
      redirect_to root_path, alert: "Invalid OAuth state"
      return
    end

    project_id = session.delete(:discord_project_id)
    @project = current_account.projects.find(project_id)

    code = params[:code]
    unless code
      redirect_to project_settings_path(@project),
                  alert: "Discord did not return an authorization code."
      return
    end

    data = exchange_code(code)

    if data["webhook"].present?
      save_discord_credentials(data)
      redirect_to project_settings_path(@project),
                  notice: "Discord connected successfully! Notifications will be sent to ##{data.dig('webhook', 'name') || data.dig('webhook', 'channel_id')}."
    else
      Rails.logger.error "Discord OAuth error: #{data.inspect}"
      redirect_to project_settings_path(@project),
                  alert: "Failed to connect Discord: #{data['error_description'] || data['error'] || 'Unknown error'}"
    end
  end

  private

  def callback_url
    discord_oauth_callback_url
  end

  def exchange_code(code)
    response = Faraday.post("https://discord.com/api/oauth2/token") do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = {
        client_id: ENV["DISCORD_CLIENT_ID"],
        client_secret: ENV["DISCORD_CLIENT_SECRET"],
        grant_type: "authorization_code",
        code: code,
        redirect_uri: callback_url
      }
    end

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    Rails.logger.error "Discord OAuth response parse error: #{e.message}"
    { "error" => "invalid_response" }
  end

  def save_discord_credentials(data)
    webhook = data["webhook"]
    guild = data["guild"]

    settings = @project.settings || {}
    settings["discord_webhook_url"]   = webhook["url"]
    settings["discord_webhook_id"]    = webhook["id"]
    settings["discord_channel_id"]    = webhook["channel_id"]
    settings["discord_guild_id"]      = guild&.dig("id") || webhook["guild_id"]
    settings["discord_guild_name"]    = guild&.dig("name")
    settings["discord_webhook_name"]  = webhook["name"]

    @project.update!(settings: settings)
  end

  def set_project
    @project = current_account.projects.find(params[:project_id] || params[:id])
  end
end
