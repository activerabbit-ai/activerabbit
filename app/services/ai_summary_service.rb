class AiSummaryService
  SYSTEM_PROMPT = <<~PROMPT
    You are a senior Rails debugging assistant. Analyze the error context, stack/backtrace, request info, and suggest likely root cause and concrete fixes. Keep it concise, actionable, and specific to the code paths shown. If sensitive data is present, avoid echoing it.
  PROMPT

  def initialize(issue:, sample_event: nil)
    @issue = issue
    @event = sample_event
  end

  def call
    return { error: "missing_api_key", message: "OPENAI_API_KEY not configured" } if api_key.blank?

    content = build_content
    response = client_completion(content)
    { summary: response }
  rescue => e
    Rails.logger.error("AI summary failed: #{e.class}: #{e.message}")
    { error: "ai_error", message: e.message }
  end

  private

  def api_key
    ENV["OPENAI_API_KEY"]
  end

  def client_completion(content)
    require "net/http"
    require "json"

    uri = URI.parse("https://api.openai.com/v1/chat/completions")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    body = {
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: content }
      ],
      temperature: 0.2
    }

    req = Net::HTTP::Post.new(uri.request_uri)
    req["Authorization"] = "Bearer #{api_key}"
    req["Content-Type"] = "application/json"
    req.body = JSON.dump(body)

    res = http.request(req)
    raise "OpenAI error: #{res.code} #{res.body}" unless res.code.to_i.between?(200, 299)

    json = JSON.parse(res.body)
    json.dig("choices", 0, "message", "content")
  end

  def build_content
    parts = []
    parts << "Exception: #{@issue.exception_class}"
    parts << "Controller action: #{@issue.controller_action}"
    parts << "Top frame: #{@issue.top_frame}"
    parts << "Count: #{@issue.count}, First seen: #{@issue.first_seen_at}, Last seen: #{@issue.last_seen_at}"

    if @event
      parts << "\nSample event:"
      parts << "Occurred at: #{@event.occurred_at}"
      parts << "Request: #{@event.request_method} #{@event.request_path} (server: #{@event.server_name}, request_id: #{@event.request_id})"
      status = @event.context && (@event.context["error_status"] || @event.context[:error_status])
      parts << "Status: #{status}" if status

      # Backtrace
      bt = Array(@event.formatted_backtrace)
      important = bt.select { |l| l.include?("/app/") || l.include?("/controllers/") || l.include?("/models/") || l.include?("/services/") }
      important = bt.first(15) if important.empty?
      parts << "Backtrace (important):\n#{important.join("\n")}"

      routing = @event.context && (@event.context["routing"] || @event.context[:routing])
      if routing && routing["params"]
        redacted_params = routing["params"].dup
        redacted_params.each { |k, v| redacted_params[k] = "[SCRUBBED]" if k.to_s =~ /password|token|secret|key/i }
        parts << "Params: #{redacted_params.to_json}"
      end
    end

    parts.join("\n")
  end
end
