class SlackAuthController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project_for_authorize, only: [:authorize]

  def authorize
    client_id = ENV["SLACK_CLIENT_ID"]
    scopes = %w[chat:write channels:read groups:read].join(",")

    slack_url = "https://slack.com/oauth/v2/authorize?client_id=#{client_id}&scope=#{scopes}&redirect_uri=#{callback_url}&state=#{@project.id}"

    redirect_to slack_url, allow_other_host: true
  end

  def callback
    project_id = params[:state]
    @project = current_user.projects.find(project_id)

    code = params[:code]
    unless code
      redirect_to @project, alert: "Slack did not send the authorization code"
      return
    end

    data = exchange_code_for_token(code)
    if data["ok"]
      save_slack_credentials(data)

      slack_service = SlackConnectService.new(@project.slack_access_token)
      channel_id = slack_service.create_channel("active_rabbit_alert")

      @project.update(slack_channel_id: channel_id) if channel_id

      redirect_to @project, notice: "Slack connected successfully"
    else
      logger.error "Slack OAuth error: #{data.inspect}"
      redirect_to @project, alert: "Failed to connect Slack"
    end
  end

  private

  def callback_url
    slack_oauth_callback_url
  end

  def exchange_code_for_token(code)
    conn = Faraday.new(url: "https://slack.com")
    response = conn.post(
      "/api/oauth.v2.access",
      { code:, redirect_uri: callback_url },
      {
        "Authorization" =>
          "Basic #{Base64.strict_encode64("#{ENV['SLACK_CLIENT_ID']}:#{ENV['SLACK_CLIENT_SECRET']}")}"
      }
    )

    JSON.parse(response.body)
  end

  def save_slack_credentials(data)
    @project.update!(
      slack_access_token: data["access_token"],
      slack_team_id: data.dig("team", "id"),
      slack_team_name: data.dig("team", "name")
    )
  end

  def set_project_for_authorize
    @project = current_user.projects.find(params[:project_id] || params[:id])
  end
end
