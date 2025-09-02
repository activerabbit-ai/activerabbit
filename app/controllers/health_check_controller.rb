class HealthCheckController < ActionController::Base
  # Completely bypass all ApplicationController authentication and callbacks
  # This controller inherits directly from ActionController::Base
  
  def show
    # Simple health check - return 200 if Rails can boot
    render json: { 
      status: 'ok', 
      timestamp: Time.current.iso8601,
      rails_env: Rails.env 
    }, status: :ok
  end
end
