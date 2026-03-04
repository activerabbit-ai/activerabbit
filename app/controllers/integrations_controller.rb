class IntegrationsController < ApplicationController
  skip_before_action :authenticate_user!
  layout "public"

  def slack
    @slack_client_id = ENV["SLACK_CLIENT_ID"]
  end

  def support
  end

  def discord
    @discord_client_id = ENV["DISCORD_CLIENT_ID"]
  end
end
