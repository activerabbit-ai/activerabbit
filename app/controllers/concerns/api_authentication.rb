module ApiAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :log_api_request
    before_action :authenticate_api_token!
    before_action :set_current_project
    before_action :check_project_active

    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :render_validation_errors
    rescue_from StandardError, with: :render_internal_error
  end

  private

  def log_api_request
    Rails.logger.info "🚀 API REQUEST from Remote App:"
    Rails.logger.info "  Method: #{request.method}"
    Rails.logger.info "  URL: #{request.url}"
    Rails.logger.info "  Headers: #{request.headers.to_h.select { |k, v| k.start_with?('HTTP_') || k == 'X-Project-Token' }}"
    Rails.logger.info "  Body: #{request.body.read}"
    request.body.rewind # Reset body for further processing
    Rails.logger.info "  Params: #{params.inspect}"
    Rails.logger.info "🚀 END API REQUEST"
  end

  def authenticate_api_token!
    token_header = request.headers["X-Project-Token"]

    if token_header.blank?
      render_unauthorized("Missing X-Project-Token header")
      return
    end

    @current_api_token = ApiToken.authenticate(token_header)

    if @current_api_token.nil?
      render_unauthorized("Invalid or inactive token")
      return
    end

    # Set tenant for the duration of this request
    ActsAsTenant.current_tenant = @current_api_token.project.account

    # Rate limiting per token
    rate_limit_key = "api_token:#{@current_api_token.id}"
    if rate_limited?(rate_limit_key)
      render_rate_limited
      nil
    end
  end

  def set_current_project
    @current_project = @current_api_token&.project
  end

  def check_project_active
    unless @current_project&.active?
      render_forbidden("Project is inactive")
    end
  end

  def rate_limited?(key, limit: 1000, window: 60) # 1000 requests per minute
    current_count = Rails.cache.read("rate_limit:#{key}") || 0

    if current_count >= limit
      true
    else
      Rails.cache.write("rate_limit:#{key}", current_count + 1, expires_in: window.seconds)
      false
    end
  end

  def render_unauthorized(message = "Unauthorized")
    render json: {
      error: "unauthorized",
      message: message
    }, status: :unauthorized
  end

  def render_forbidden(message = "Forbidden")
    render json: {
      error: "forbidden",
      message: message
    }, status: :forbidden
  end

  def render_rate_limited
    render json: {
      error: "rate_limited",
      message: "Too many requests. Please slow down."
    }, status: :too_many_requests
  end

  def render_not_found
    render json: {
      error: "not_found",
      message: "Resource not found"
    }, status: :not_found
  end

  def render_validation_errors(exception)
    render json: {
      error: "validation_failed",
      message: "Validation failed",
      details: exception.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  def render_internal_error(exception)
    Rails.logger.error "API Error: #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n")

    render json: {
      error: "internal_error",
      message: "An internal error occurred"
    }, status: :internal_server_error
  end

  def render_success(data = nil, message: "Success")
    response = { status: "success", message: message }
    response[:data] = data if data
    render json: response, status: :ok
  end

  def render_created(data = nil, message: "Created")
    response = { status: "created", message: message }
    response[:data] = data if data
    render json: response, status: :created
  end
end
