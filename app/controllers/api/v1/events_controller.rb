class Api::V1::EventsController < Api::BaseController

    # POST /api/v1/events/errors
  def create_error
    Rails.logger.info "=== DEBUG: create_error called ==="
    Rails.logger.info "Raw params: #{params.inspect}"
    Rails.logger.info "Current project: #{@current_project.inspect}"
    Rails.logger.info "Current API token: #{@current_api_token.inspect}"

    # Check if project exists
    unless @current_project
      Rails.logger.error "ERROR: @current_project is nil!"
      render json: { error: 'project_not_found', message: 'Project not found' }, status: :not_found
      return
    end

    payload = sanitize_error_payload(params)
    Rails.logger.info "Sanitized payload: #{payload.inspect}"

    # Validate required fields
    validate_error_payload!(payload)

    # Process in background for better performance
    # Ensure payload is JSON-serializable by converting to hash and stringifying
    serializable_payload = JSON.parse(payload.to_h.to_json)
    Rails.logger.info "Serializable payload: #{serializable_payload.inspect}"
    Rails.logger.info "Calling ErrorIngestJob.perform_async(#{@current_project.id}, payload)"
    ErrorIngestJob.perform_async(@current_project.id, serializable_payload)

    render_created(
      {
        project_id: @current_project.id,
        exception_class: payload[:exception_class] || payload[:exception_type]
      },
      message: 'Error event queued for processing'
    )
  rescue => e
    Rails.logger.error "ERROR in create_error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: 'processing_error', message: e.message }, status: :internal_server_error
  end

  # POST /api/v1/events/performance
  def create_performance

    Rails.logger.info "=== DEBUG: create_performance called ==="
    Rails.logger.info "Raw params: #{params.inspect}"
    Rails.logger.info "Current project: #{@current_project.inspect}"

    # Check if project exists
    unless @current_project
      Rails.logger.error "ERROR: @current_project is nil!"
      render json: { error: 'project_not_found', message: 'Project not found' }, status: :not_found
      return
    end

    payload = sanitize_performance_payload(params)
    Rails.logger.info "Sanitized payload: #{payload.inspect}"

    # Validate required fields
    validate_performance_payload!(payload)

    # Process in background
    # Ensure payload is JSON-serializable by converting to hash and stringifying
    serializable_payload = JSON.parse(payload.to_h.to_json)
    Rails.logger.info "Serializable payload: #{serializable_payload.inspect}"
    Rails.logger.info "Calling PerformanceIngestJob.perform_async(#{@current_project.id}, payload)"
    PerformanceIngestJob.perform_async(@current_project.id, serializable_payload)

    render_created(
      {
        project_id: @current_project.id,
        target: payload[:controller_action] || payload[:job_class]
      },
      message: 'Performance event queued for processing'
    )
  rescue => e
    Rails.logger.error "ERROR in create_performance: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: 'processing_error', message: e.message }, status: :internal_server_error
  end

  # POST /api/v1/events/batch
  def create_batch
    Rails.logger.info "=== DEBUG: create_batch called ==="
    Rails.logger.info "Raw params: #{params.inspect}"

    events = params[:events] || []
    Rails.logger.info "Events array: #{events.inspect}"

    if events.empty?
      render json: {
        error: 'validation_failed',
        message: 'No events provided'
      }, status: :unprocessable_entity
      return
    end

    if events.size > 100 # Batch size limit
      render json: {
        error: 'validation_failed',
        message: 'Batch size exceeds maximum of 100 events'
      }, status: :unprocessable_entity
      return
    end

    batch_id = SecureRandom.uuid
    processed_count = 0

    events.each do |event_data|
      # Extract the actual payload from the data field first
      actual_data = event_data[:data] || event_data['data'] || event_data

      # Event type can be at top level or inside the data
      event_type = event_data[:event_type] || event_data['event_type'] ||
                   actual_data[:event_type] || actual_data['event_type']
      Rails.logger.info "Processing event with type: #{event_type.inspect}"
      Rails.logger.info "Event data structure: #{event_data.keys.inspect}"
      Rails.logger.info "Actual data structure: #{actual_data.keys.inspect if actual_data.respond_to?(:keys)}"

      case event_type
      when 'error'
        Rails.logger.info "Processing error event. actual_data: #{actual_data.inspect}"
        payload = sanitize_error_payload(actual_data)
        Rails.logger.info "Error payload after sanitization: #{payload.inspect}"

        if valid_error_payload?(payload)
          Rails.logger.info "Payload is valid, queuing job"
          serializable_payload = JSON.parse(payload.to_h.to_json)
          Rails.logger.info "Calling ErrorIngestJob.perform_async(#{@current_project.id}, payload, #{batch_id})"
          ErrorIngestJob.perform_async(@current_project.id, serializable_payload, batch_id)
          processed_count += 1
        else
          Rails.logger.info "Payload validation failed, skipping"
        end
      when 'performance'
        payload = sanitize_performance_payload(actual_data)
        next unless valid_performance_payload?(payload)
        serializable_payload = JSON.parse(payload.to_h.to_json)
        PerformanceIngestJob.perform_async(@current_project.id, serializable_payload, batch_id)
        processed_count += 1
      end
    end

    render_created(
      {
        batch_id: batch_id,
        processed_count: processed_count,
        total_count: events.size,
        project_id: @current_project.id
      },
      message: 'Batch events queued for processing'
    )
  end

  # POST /api/v1/test/connection
  def test_connection
    render json: {
      status: 'success',
      message: 'ActiveRabbit connection successful!',
      project_id: @current_project.id,
      project_name: @current_project.name,
      timestamp: Time.current.iso8601,
      gem_version: params[:gem_version] || 'unknown'
    }
  end

  private

  def sanitize_error_payload(params)
    # Extract context data for better field mapping
    context = params[:context] || params['context'] || {}
    request_context = context[:request] || context['request'] || {}

    {
      exception_class: params[:exception_class] || params['exception_class'] || params[:exception_type] || params['exception_type'] || params[:type] || params['type'],
      message: params[:message] || params['message'],
      backtrace: normalize_backtrace(params[:backtrace] || params['backtrace'] || []),
      controller_action: params[:controller_action] || params['controller_action'] || extract_controller_action(request_context),
      request_path: params[:request_path] || params['request_path'] || request_context[:path] || request_context['path'],
      request_method: params[:request_method] || params['request_method'] || request_context[:method] || request_context['method'],
      user_id: params[:user_id] || params['user_id'],
      environment: params[:environment] || params['environment'] || 'production',
      release_version: params[:release_version] || params['release_version'],
      occurred_at: parse_timestamp(params[:occurred_at] || params['occurred_at'] || params[:timestamp] || params['timestamp']),
      context: context,
      server_name: params[:server_name] || params['server_name'],
      request_id: params[:request_id] || params['request_id']
    }
  end

  def sanitize_performance_payload(params)
    {
      controller_action: params[:controller_action] || params['controller_action'] || params[:name] || params['name'],
      job_class: params[:job_class] || params['job_class'],
      request_path: params[:request_path] || params['request_path'],
      request_method: params[:request_method] || params['request_method'],
      duration_ms: parse_float(params[:duration_ms] || params['duration_ms']),
      db_duration_ms: parse_float(params[:db_duration_ms] || params['db_duration_ms']),
      view_duration_ms: parse_float(params[:view_duration_ms] || params['view_duration_ms']),
      allocations: parse_int(params[:allocations] || params['allocations']),
      sql_queries_count: parse_int(params[:sql_queries_count] || params['sql_queries_count']),
      user_id: params[:user_id] || params['user_id'],
      environment: params[:environment] || params['environment'] || 'production',
      release_version: params[:release_version] || params['release_version'],
      occurred_at: parse_timestamp(params[:occurred_at] || params['occurred_at']),
      context: params[:context] || params['context'] || {},
      server_name: params[:server_name] || params['server_name'],
      request_id: params[:request_id] || params['request_id']
    }
  end

    def validate_error_payload!(payload)
    errors = []

    errors << 'exception_class is required' if payload[:exception_class].blank?
    errors << 'message is required' if payload[:message].blank?

    if errors.any?
      render json: {
        error: 'validation_failed',
        message: 'Invalid error payload',
        details: errors
      }, status: :unprocessable_entity
      return false
    end

    true
  end

  def validate_performance_payload!(payload)
    errors = []

    errors << 'duration_ms is required' if payload[:duration_ms].blank?
    errors << 'controller_action or job_class is required' if payload[:controller_action].blank? && payload[:job_class].blank?

    if errors.any?
      render json: {
        error: 'validation_failed',
        message: 'Invalid performance payload',
        details: errors
      }, status: :unprocessable_entity
      return false
    end

    true
  end

  def valid_error_payload?(payload)
    (payload[:exception_class].present? || payload[:exception_type].present?) && payload[:message].present?
  end

  def valid_performance_payload?(payload)
    payload[:duration_ms].present? &&
    (payload[:controller_action].present? || payload[:request_path].present?)
  end

  def parse_timestamp(value)
    return Time.current if value.blank?

    case value
    when String
      Time.parse(value) rescue Time.current
    when Integer
      Time.at(value) rescue Time.current
    else
      Time.current
    end
  end

  def parse_float(value)
    return nil if value.blank?
    value.to_f rescue nil
  end

  def parse_int(value)
    return nil if value.blank?
    value.to_i rescue nil
  end

  def extract_controller_action(request_context)
    controller = request_context[:controller] || request_context['controller']
    action = request_context[:action] || request_context['action']

    if controller && action
      "#{controller}##{action}"
    elsif controller
      controller
    else
      "unknown"
    end
  end

  def normalize_backtrace(backtrace)
    return [] if backtrace.blank?

    # Handle array of strings (normal case)
    return backtrace if backtrace.is_a?(Array) && backtrace.first.is_a?(String)

    # Handle array of hashes/parameters (from gem)
    if backtrace.is_a?(Array)
      backtrace.map do |frame|
        if frame.is_a?(Hash) || frame.respond_to?(:[])
          # Extract the 'line' field which contains the full stack frame
          frame[:line] || frame['line'] || frame.to_s
        else
          frame.to_s
        end
      end
    else
      # Handle string backtrace
      backtrace.to_s.split("\n")
    end
  end
end
