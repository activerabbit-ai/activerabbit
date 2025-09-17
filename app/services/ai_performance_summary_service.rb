class AiPerformanceSummaryService
  SYSTEM_PROMPT = <<~PROMPT
    You are a senior Rails performance engineer. Analyze the performance target, recent stats, and a sample event.
    Provide a concise Root Cause Analysis (RCA), concrete optimization steps, and suggested tests/monitoring.
    Focus on controller action and database usage; include specific ActiveRecord or N+1 guidance when applicable.
  PROMPT

  def initialize(target:, stats:, sample_event: nil)
    @target = target
    @stats = stats || {}
    @event = sample_event
  end

  def call
    return { error: 'missing_api_key', message: 'OPENAI_API_KEY not configured' } if api_key.blank?

    content = build_content
    response = client_completion(content)
    { summary: response }
  rescue => e
    Rails.logger.error("AI perf summary failed: #{e.class}: #{e.message}")
    { error: 'ai_error', message: e.message }
  end

  private

  def api_key
    ENV['OPENAI_API_KEY']
  end

  def client_completion(content)
    require 'net/http'
    require 'json'

    uri = URI.parse('https://api.openai.com/v1/chat/completions')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    body = {
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: content }
      ],
      temperature: 0.2
    }

    req = Net::HTTP::Post.new(uri.request_uri)
    req['Authorization'] = "Bearer #{api_key}"
    req['Content-Type'] = 'application/json'
    req.body = JSON.dump(body)

    res = http.request(req)
    raise "OpenAI error: #{res.code} #{res.body}" unless res.code.to_i.between?(200, 299)

    json = JSON.parse(res.body)
    json.dig('choices', 0, 'message', 'content')
  end

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


