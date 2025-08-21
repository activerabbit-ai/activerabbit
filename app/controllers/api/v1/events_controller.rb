class Api::V1::EventsController < Api::BaseController

    # POST /api/v1/events/errors
  def create_error
    payload = sanitize_error_payload(params)

    # Validate required fields
    validate_error_payload!(payload)

    # Process in background for better performance
    # Ensure payload is JSON-serializable by converting to hash and stringifying
    serializable_payload = JSON.parse(payload.to_h.to_json)
    ErrorIngestJob.perform_async(@current_project.id, serializable_payload)

    render_created(
      {
        project_id: @current_project.id,
        exception_class: payload[:exception_class] || payload[:exception_type]
      },
      message: 'Error event queued for processing'
    )
  end

  # POST /api/v1/events/performance
  def create_performance
    payload = sanitize_performance_payload(params)

    # Validate required fields
    validate_performance_payload!(payload)

    # Process in background
    # Ensure payload is JSON-serializable by converting to hash and stringifying
    serializable_payload = JSON.parse(payload.to_h.to_json)
    PerformanceIngestJob.perform_async(@current_project.id, serializable_payload)

    render_created(
      {
        project_id: @current_project.id,
        target: payload[:controller_action] || payload[:job_class]
      },
      message: 'Performance event queued for processing'
    )
  end

  # POST /api/v1/events/batch
  def create_batch
    events = params[:events] || []

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
      event_type = event_data[:event_type] || event_data['event_type']

      case event_type
      when 'error'
        payload = sanitize_error_payload(event_data)
        next unless valid_error_payload?(payload)
        serializable_payload = JSON.parse(payload.to_h.to_json)
        ErrorIngestJob.perform_async(@current_project.id, serializable_payload, batch_id)
        processed_count += 1
      when 'performance'
        payload = sanitize_performance_payload(event_data)
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

  private

  def sanitize_error_payload(params)
    {
      exception_class: params[:exception_class] || params['exception_class'] || params[:exception_type] || params['exception_type'],
      message: params[:message] || params['message'],
      backtrace: params[:backtrace] || params['backtrace'],
      controller_action: params[:controller_action] || params['controller_action'],
      request_path: params[:request_path] || params['request_path'],
      request_method: params[:request_method] || params['request_method'],
      user_id: params[:user_id] || params['user_id'],
      environment: params[:environment] || params['environment'] || 'production',
      release_version: params[:release_version] || params['release_version'],
      occurred_at: parse_timestamp(params[:occurred_at] || params['occurred_at']),
      context: params[:context] || params['context'] || {},
      server_name: params[:server_name] || params['server_name'],
      request_id: params[:request_id] || params['request_id']
    }
  end

  def sanitize_performance_payload(params)
    {
      controller_action: params[:controller_action] || params['controller_action'],
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
    payload[:exception_type].present? && payload[:message].present?
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
end
