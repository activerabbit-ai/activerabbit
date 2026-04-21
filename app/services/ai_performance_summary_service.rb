class AiPerformanceSummaryService
  include AiProviderChat

  SYSTEM_PROMPT = <<~PROMPT
    You are a senior Rails performance engineer. Analyze the performance target, recent stats, and a sample event.
    Provide a concise Root Cause Analysis (RCA), concrete optimization steps, and suggested tests/monitoring.
    Focus on controller action and database usage; include specific ActiveRecord or N+1 guidance when applicable.
  PROMPT

  def initialize(account:, target:, stats:, sample_event: nil)
    @account = account
    @target = target
    @stats = stats || {}
    @event = sample_event
  end

  def call
    chat = ai_chat(@account)
    return { error: "missing_config", message: "No AI provider configured" } unless chat

    response = chat.with_instructions(SYSTEM_PROMPT).ask(build_content)
    { summary: response.content }
  rescue => e
    Rails.logger.error("AI perf summary failed: #{e.class}: #{e.message}")
    { error: "ai_error", message: e.message }
  end

  private

  def build_content
    parts = []
    parts << "Target: #{@target}"
    parts << "Recent stats:"
    parts << "- total_requests: #{@stats[:total_requests]}"
    parts << "- total_errors: #{@stats[:total_errors]}"
    parts << "- error_rate: #{@stats[:error_rate]}%" if @stats[:error_rate]
    parts << "- avg_ms: #{@stats[:avg_ms]}" if @stats[:avg_ms]
    parts << "- p95_ms: #{@stats[:p95_ms]}" if @stats[:p95_ms]

    if @event
      parts << "\nSample event:"
      parts << "duration_ms: #{@event.duration_ms} (db: #{@event.db_duration_ms}, view: #{@event.view_duration_ms})"
      parts << "sql_queries_count: #{@event.sql_queries_count}, allocations: #{@event.allocations}"
      parts << "request: #{@event.request_method} #{@event.request_path} (server: #{@event.server_name}, request_id: #{@event.request_id})"
    end

    parts << "\nWrite: RCA, suggested code changes, and tests."
    parts.join("\n")
  end
end
