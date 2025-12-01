class Api::BaseController < ActionController::API
  include ApiAuthentication

  # Disable CSRF for API endpoints (ActionController::API doesn't have CSRF protection by default)

  # Set JSON content type
  before_action :set_content_type

  # Payload size limiting (10MB max)
  before_action :check_payload_size

  rescue_from ActionDispatch::Http::Parameters::ParseError do |e|
    render json: {
      error: "bad_request",
      message: "Invalid request parameters: #{e.message}"
    }, status: :bad_request
  end

  private

  def json_request?
    request.format.json?
  end

  def set_content_type
    response.content_type = "application/json"
  end

  def check_payload_size
    max_size = 10.megabytes

    if request.content_length && request.content_length > max_size
      render json: {
        error: "payload_too_large",
        message: "Payload size exceeds maximum of #{max_size / 1.megabyte}MB"
      }, status: :payload_too_large
    end
  end
end
