class SettingsController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!

  def index
    @settings = {
      app_name: 'ActiveRabbit',
      account_name: current_account&.name,
      total_projects: current_account&.projects&.count || 0,
      total_users: current_account&.users&.count || 0,
      account_created: current_account&.created_at,
      debug_mode: Rails.env.development?
    }
  end
end
