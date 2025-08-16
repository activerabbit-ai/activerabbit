class Admin::DashboardController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!

  def index
    # Dashboard metrics and data
    @stats = {
      total_users: User.count,
      active_sessions: User.where('current_sign_in_at > ?', 1.hour.ago).count,
      total_revenue: 0, # Placeholder for actual revenue calculation
      uptime: '99.9%'
    }

    @recent_users = User.order(created_at: :desc).limit(5)
    @system_health = {
      database: 'healthy',
      redis: 'healthy',
      sidekiq: 'healthy'
    }
  end
end
