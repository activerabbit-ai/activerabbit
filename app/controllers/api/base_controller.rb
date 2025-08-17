class Api::BaseController < ActionController::API
  include ApiAuthentication

  # Disable CSRF for API endpoints
  skip_before_action :verify_authenticity_token, if: :json_request?

  # Set JSON content type
  before_action :set_content_type

  # Payload size limiting (10MB max)
  before_action :check_payload_size

  private

  def json_request?
    request.format.json?
  end

  def set_content_type
    response.content_type = 'application/json'
  end

  def check_payload_size
    max_size = 10.megabytes

    if request.content_length && request.content_length > max_size
      render json: {
        error: 'payload_too_large',
        message: "Payload size exceeds maximum of #{max_size / 1.megabyte}MB"
      }, status: :payload_too_large
    end
  end
end
