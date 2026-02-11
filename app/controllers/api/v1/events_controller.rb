class Api::V1::EventsController < Api::BaseController
  # POST /api/v1/events/errors
  def create_error
    unless @current_project
      render json: { error: "project_not_found", message: "Project not found" }, status: :not_found
      return
    end

    payload = sanitize_error_payload(params)

    # Validate required fields; return 422 on failure
    unless validate_error_payload!(payload)
      return
    end

    # Process in background for better performance
    serializable_payload = JSON.parse(payload.to_h.to_json)
    enqueue_error_ingest(@current_project.id, serializable_payload)

    render_created(
      {
        project_id: @current_project.id,
        exception_class: payload[:exception_class] || payload[:exception_type]
      },
      message: "Error event queued for processing"
    )
  rescue => e
    Rails.logger.error "ERROR in create_error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: "processing_error", message: e.message }, status: :internal_server_error
  end

  # POST /api/v1/events/performance
  def create_performance
    unless @current_project
      render json: { error: "project_not_found", message: "Project not found" }, status: :not_found
      return
    end

    payload = sanitize_performance_payload(params)

    # Validate required fields
    return unless validate_performance_payload!(payload)

    # Process in background
    serializable_payload = JSON.parse(payload.to_h.to_json)
    enqueue_performance_ingest(@current_project.id, serializable_payload)

    render_created(
      {
        project_id: @current_project.id,
        target: payload[:controller_action] || payload[:job_class]
      },
      message: "Performance event queued for processing"
    )
  rescue => e
    Rails.logger.error "ERROR in create_performance: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: "processing_error", message: e.message }, status: :internal_server_error
  end

  # POST /api/v1/events/batch
  def create_batch
    unless @current_project
      render json: { error: "project_not_found", message: "Project not found" }, status: :not_found
      return
    end

    events = params[:events] || []

    if events.empty?
      render json: {
        error: "validation_failed",
        message: "No events provided"
      }, status: :unprocessable_entity
      return
    end

    if events.size > 500 # Batch size limit (raised from 100 for high-throughput clients)
      render json: {
        error: "validation_failed",
        message: "Batch size exceeds maximum of 500 events"
      }, status: :unprocessable_entity
      return
    end

    batch_id = SecureRandom.uuid
    processed_count = 0

    events.each do |event_data|
      next if event_data.nil?
      # Extract the actual payload from the data field first
      actual_data = event_data[:data] || event_data["data"] || event_data
      next if actual_data.nil?

      # Detect event type from multiple sources:
      # 1. event_type field (explicit)
      # 2. type field at top level (client convention)
      # 3. Infer from the data name field (slow_query, sidekiq.job, etc.)
      event_type = event_data[:event_type] || event_data["event_type"] ||
                   actual_data[:event_type] || actual_data["event_type"] ||
                   event_data[:type] || event_data["type"]

      # Auto-detect type from data name when type is nil
      if event_type.blank?
        data_name = actual_data[:name] || actual_data["name"]
        event_type = infer_event_type(data_name)
      end

      case event_type
      when "error"
        payload = sanitize_error_payload(actual_data)
        if valid_error_payload?(payload)
          serializable_payload = JSON.parse(payload.to_h.to_json)
          enqueue_error_ingest(@current_project.id, serializable_payload, batch_id)
          processed_count += 1
        end
      when "performance"
        payload = sanitize_performance_payload(actual_data)
        next unless valid_performance_payload?(payload)
        serializable_payload = JSON.parse(payload.to_h.to_json)
        enqueue_performance_ingest(@current_project.id, serializable_payload, batch_id)
        processed_count += 1
      else
        # Skip unknown event types silently (metrics, logs, etc.)
        next
      end
    end

    render_created(
      {
        batch_id: batch_id,
        processed_count: processed_count,
        total_count: events.size,
        project_id: @current_project.id
      },
      message: "Batch events queued for processing"
    )
  rescue => e
    Rails.logger.error "ERROR in create_batch: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: "processing_error", message: e.message }, status: :internal_server_error
  end

  # POST /api/v1/test/connection
  def test_connection
    render json: {
      status: "success",
      message: "ActiveRabbit connection successful!",
      project_id: @current_project.id,
      project_name: @current_project.name,
      timestamp: Time.current.iso8601,
      gem_version: params[:gem_version] || "unknown"
    }
  end

  private

  def sanitize_error_payload(params)
    # Extract context data for better field mapping
    context = params[:context] || params["context"] || {}
    request_context = context[:request] || context["request"] || {}
    tags = params[:tags] || params["tags"] || {}

    {
      exception_class: params[:exception_class] || params["exception_class"] || params[:exception_type] || params["exception_type"] || params[:type] || params["type"],
      message: params[:message] || params["message"],
      backtrace: normalize_backtrace(params[:backtrace] || params["backtrace"] || []),
      # NEW: Structured stack trace with source code context (Sentry-style)
      structured_stack_trace: params[:structured_stack_trace] || params["structured_stack_trace"],
      culprit_frame: params[:culprit_frame] || params["culprit_frame"],
      controller_action: params[:controller_action] || params["controller_action"] || extract_controller_action(request_context) || extract_controller_action_from_job(context),
      request_path: params[:request_path] || params["request_path"] || request_context[:path] || request_context["path"],
      request_method: params[:request_method] || params["request_method"] || request_context[:method] || request_context["method"],
      user_id: params[:user_id] || params["user_id"],
      environment: params[:environment] || params["environment"] || "production",
      release_version: params[:release_version] || params["release_version"],
      occurred_at: parse_timestamp(params[:occurred_at] || params["occurred_at"] || params[:timestamp] || params["timestamp"]),
      context: context,
      tags: tags,
      server_name: params[:server_name] || params["server_name"],
      request_id: params[:request_id] || params["request_id"]
    }
  end

  def extract_controller_action_from_job(context)
    job = context[:job] || context["job"]
    return nil unless job.is_a?(Hash)

    (job[:worker_class] || job["worker_class"] || job[:job_class] || job["job_class"]).to_s.presence
  end

  def sanitize_performance_payload(params)
    md = params[:metadata] || params["metadata"] || {}
    # Self-monitoring events (slow_query, sidekiq_job_completed, etc.) nest
    # duration_ms and other fields inside a "properties" hash.
    props = params[:properties] || params["properties"] || {}

    # Derive controller_action from metadata if not explicitly provided
    ctrl_action = params[:controller_action] || params["controller_action"]
    if ctrl_action.blank?
      c = md[:controller] || md["controller"]
      a = md[:action] || md["action"]
      ctrl_action = "#{c}##{a}" if c && a
    end

    # Also try to derive from job context
    if ctrl_action.blank?
      ctx = params[:context] || params["context"] || {}
      job = ctx[:job] || ctx["job"] || {}
      ctrl_action = (job[:worker_class] || job["worker_class"]).to_s.presence
    end

    {
      controller_action: ctrl_action || params[:name] || params["name"],
      job_class: params[:job_class] || params["job_class"] || (props[:worker_class] || props["worker_class"]),
      request_path: params[:request_path] || params["request_path"] || md[:path] || md["path"],
      request_method: params[:request_method] || params["request_method"] || md[:method] || md["method"],
      duration_ms: parse_float(params[:duration_ms] || params["duration_ms"] || props[:duration_ms] || props["duration_ms"]),
      db_duration_ms: parse_float(params[:db_duration_ms] || params["db_duration_ms"] || md[:db_runtime] || md["db_runtime"]),
      view_duration_ms: parse_float(params[:view_duration_ms] || params["view_duration_ms"] || md[:view_runtime] || md["view_runtime"]),
      allocations: parse_int(params[:allocations] || params["allocations"] || md[:allocations] || md["allocations"]),
      sql_queries_count: parse_int(params[:sql_queries_count] || params["sql_queries_count"]),
      user_id: params[:user_id] || params["user_id"],
      environment: params[:environment] || params["environment"] || "production",
      release_version: params[:release_version] || params["release_version"],
      occurred_at: parse_timestamp(params[:occurred_at] || params["occurred_at"] || params[:timestamp] || params["timestamp"]),
      context: (params[:context] || params["context"] || {}).presence || md, # fallback to metadata for visibility
      server_name: params[:server_name] || params["server_name"],
      request_id: params[:request_id] || params["request_id"]
    }
  end

  def validate_error_payload!(payload)
    errors = []

    errors << "exception_class is required" if payload[:exception_class].blank?
    errors << "message is required" if payload[:message].blank?

    if errors.any?
      render json: {
        error: "validation_failed",
        message: "Invalid error payload",
        details: errors
      }, status: :unprocessable_entity
      return false
    end

    true
  end

  def validate_performance_payload!(payload)
    errors = []

    errors << "duration_ms is required" if payload[:duration_ms].blank?
    errors << "controller_action or job_class is required" if payload[:controller_action].blank? && payload[:job_class].blank?

    if errors.any?
      render json: {
        error: "validation_failed",
        message: "Invalid performance payload",
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
    controller = request_context[:controller] || request_context["controller"]
    action = request_context[:action] || request_context["action"]

    if controller && action
      "#{controller}##{action}"
    elsif controller
      controller
    else
      "unknown"
    end
  end

  # Infer event type from the data name field when type is nil.
  # The activerabbit-ai gem sends self-monitoring events with type=nil
  # but with descriptive names like "slow_query", "sidekiq.job", etc.
  PERFORMANCE_EVENT_NAMES = %w[
    controller.action sidekiq.job sidekiq_job_completed
    slow_query slow_template_render slow_partial_render
    memory_snapshot
  ].freeze

  ERROR_EVENT_NAMES = %w[
    exception unhandled_error sidekiq_job_failed
  ].freeze

  def infer_event_type(name)
    return nil if name.blank?

    name_str = name.to_s.downcase
    return "performance" if PERFORMANCE_EVENT_NAMES.include?(name_str)
    return "performance" if name_str.start_with?("slow_", "sidekiq")
    return "error" if ERROR_EVENT_NAMES.include?(name_str)
    return "error" if name_str.include?("error") || name_str.include?("exception")

    nil # Unknown — skip
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
          frame[:line] || frame["line"] || frame.to_s
        else
          frame.to_s
        end
      end
    else
      # Handle string backtrace
      backtrace.to_s.split("\n")
    end
  end

  # If Sidekiq/Redis is down (or queue push fails), fall back to synchronous ingest so
  # customers still see new errors/performance data in the UI.
  def enqueue_error_ingest(project_id, payload, batch_id = nil)
    ErrorIngestJob.perform_async(project_id, payload, batch_id)
  rescue => e
    Rails.logger.error("[ActiveRabbit] ErrorIngestJob.perform_async failed, falling back to inline perform: #{e.class}: #{e.message}")
    ErrorIngestJob.new.perform(project_id, payload, batch_id)
  end

  def enqueue_performance_ingest(project_id, payload, batch_id = nil)
    PerformanceIngestJob.perform_async(project_id, payload, batch_id)
  rescue => e
    Rails.logger.error("[ActiveRabbit] PerformanceIngestJob.perform_async failed, falling back to inline perform: #{e.class}: #{e.message}")
    PerformanceIngestJob.new.perform(project_id, payload, batch_id)
  end
end
