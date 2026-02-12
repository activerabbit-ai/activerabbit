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

    if events.size > 500 # Batch size limit
      render json: {
        error: "validation_failed",
        message: "Batch size exceeds maximum of 500 events"
      }, status: :unprocessable_entity
      return
    end

    # Dedup: if the client sends a batch_id (or X-Request-Id), reject retries.
    # Prevents snowball effect when queue backs up → slow responses → client retries → more jobs.
    client_batch_id = params[:batch_id] || request.headers["X-Request-Id"]
    if client_batch_id.present?
      dedup_key = "batch_dedup:#{@current_project.id}:#{client_batch_id}"
      already_seen = Sidekiq.redis { |c| c.set(dedup_key, "1", nx: true, ex: 300) }
      unless already_seen
        render_created({ batch_id: client_batch_id, processed_count: 0, deduplicated: true },
                       message: "Batch already processed (duplicate request)")
        return
      end
    end

    batch_id = client_batch_id || SecureRandom.uuid
    error_payloads = []
    perf_payloads = []

    events.each do |event_data|
      next if event_data.nil?
      actual_data = event_data[:data] || event_data["data"] || event_data
      next if actual_data.nil?

      # Detect event type from multiple sources:
      # 1. event_type field (explicit)
      # 2. type field at top level (client convention)
      # 3. Infer from the data name field (slow_query, sidekiq.job, etc.)
      event_type = event_data[:event_type] || event_data["event_type"] ||
                   actual_data[:event_type] || actual_data["event_type"] ||
                   event_data[:type] || event_data["type"]

      if event_type.blank?
        data_name = actual_data[:name] || actual_data["name"]
        event_type = infer_event_type(data_name)
      end

      case event_type
      when "error"
        payload = sanitize_error_payload(actual_data)
        if valid_error_payload?(payload)
          # Skip self-monitoring errors to prevent feedback loops
          # (same protection as performance events below)
          next if self_monitoring_error?(payload)
          serializable_payload = JSON.parse(payload.to_h.to_json)
          error_payloads << serializable_payload
        end
      when "performance"
        payload = sanitize_performance_payload(actual_data)
        next unless valid_performance_payload?(payload)
        # Skip self-monitoring of API endpoints to prevent feedback loops.
        # Without this, each batch request generates performance events about
        # itself, which get batched and sent back, creating infinite amplification.
        next if self_monitoring_event?(payload)
        serializable_payload = JSON.parse(payload.to_h.to_json)
        perf_payloads << serializable_payload
      end
    end

    # Bulk-enqueue to Sidekiq in 1 Redis round-trip per job class
    # (instead of N individual perform_async calls)
    processed_count = bulk_enqueue_jobs(error_payloads, perf_payloads, batch_id)

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
    Rails.logger.error e.backtrace.first(5).join("\n")
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

  # Paths that should not be recorded as performance data when the app
  # monitors itself.  Without this filter, each batch POST generates ~30
  # performance events about itself → infinite amplification loop.
  SELF_MONITORING_PATHS = %w[
    /api/v1/events/batch
    /api/v1/events/errors
    /api/v1/events/performance
    /api/v1/test/connection
  ].freeze

  SELF_MONITORING_CONTROLLERS = %w[
    Api::V1::EventsController
  ].freeze

  def self_monitoring_event?(payload)
    path = payload[:request_path].to_s
    return true if SELF_MONITORING_PATHS.include?(path)

    ctrl = payload[:controller_action].to_s
    SELF_MONITORING_CONTROLLERS.any? { |c| ctrl.start_with?(c) }
  end

  # Check if an error event originated from self-monitoring paths.
  # Prevents feedback loops: ActiveRabbit error → ingest → possibly more errors → loop.
  def self_monitoring_error?(payload)
    # Check backtrace for self-monitoring controller paths
    backtrace = payload[:backtrace]
    return false unless backtrace.is_a?(Array)

    backtrace.first(3).any? { |frame| frame.to_s.include?("api/v1/events_controller") }
  end

  # Enqueue 1 batch job per event type (instead of N individual jobs).
  # This reduces queue pressure by ~50x under high traffic.
  def bulk_enqueue_jobs(error_payloads, perf_payloads, batch_id)
    count = 0
    project_id = @current_project.id

    if error_payloads.any?
      ErrorBatchIngestJob.perform_async(project_id, error_payloads, batch_id)
      count += error_payloads.size
    end

    if perf_payloads.any?
      PerformanceBatchIngestJob.perform_async(project_id, perf_payloads, batch_id)
      count += perf_payloads.size
    end

    count
  rescue => e
    Rails.logger.error("[ActiveRabbit] batch enqueue failed (#{e.class}): #{e.message}")
    # Fallback: enqueue individually
    error_payloads.each { |p| ErrorIngestJob.perform_async(project_id, p, batch_id) rescue nil }
    perf_payloads.each { |p| PerformanceIngestJob.perform_async(project_id, p, batch_id) rescue nil }
    error_payloads.size + perf_payloads.size
  end

  # For single-event endpoints, keep inline fallback (1 event won't kill perf)
  def enqueue_error_ingest(project_id, payload, batch_id = nil)
    ErrorIngestJob.perform_async(project_id, payload, batch_id)
  rescue => e
    Rails.logger.error("[ActiveRabbit] ErrorIngestJob.perform_async failed, falling back to inline: #{e.class}: #{e.message}")
    ErrorIngestJob.new.perform(project_id, payload, batch_id)
  end

  def enqueue_performance_ingest(project_id, payload, batch_id = nil)
    PerformanceIngestJob.perform_async(project_id, payload, batch_id)
  rescue => e
    Rails.logger.error("[ActiveRabbit] PerformanceIngestJob.perform_async failed, falling back to inline: #{e.class}: #{e.message}")
    PerformanceIngestJob.new.perform(project_id, payload, batch_id)
  end
end
