class Admin::SettingsController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!

  def index
    @settings = {
      app_name: 'ActiveAgent',
      maintenance_mode: false,
      debug_mode: Rails.env.development?,
      max_users: 1000,
      session_timeout: 30
    }
  end
end
