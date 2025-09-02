class HealthController < ActionController::API
  # Minimal health controller that bypasses all ApplicationController filters
  # Inherits from ActionController::API (not Base) to avoid sessions, CSRF, etc.

  def show
    # Simple health check - return 200 if Rails can boot and respond
    render json: {
      status: 'ok',
      timestamp: Time.current.iso8601,
      rails_env: Rails.env
    }, status: :ok
  end
end
