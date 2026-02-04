class AiSummaryService
  SYSTEM_PROMPT = <<~PROMPT
    You are a senior Rails debugging assistant. Analyze the error and provide a fix.

    Use this EXACT format with proper line breaks:

    ## Root Cause

    Brief explanation here.

    ## Fix

    **Before:**

    ```ruby
    broken_code
    ```

    **After:**

    ```ruby
    fixed_code
    ```

    ## Prevention

    Brief tips here.

    IMPORTANT: You MUST have a blank line before each ``` code fence. The ``` must be alone on its own line.
  PROMPT

  def initialize(issue:, sample_event: nil)
    @issue = issue
    @event = sample_event
  end

  def call
    return { error: "missing_api_key", message: "ANTHROPIC_API_KEY not configured" } if api_key.blank?

    content = build_content
    response = client_completion(content)
    { summary: response }
  rescue => e
    Rails.logger.error("AI summary failed: #{e.class}: #{e.message}")
    { error: "ai_error", message: e.message }
  end

  private

  def api_key
    ENV["ANTHROPIC_API_KEY"]
  end

  def client_completion(content)
    require "net/http"
    require "json"

    uri = URI.parse("https://api.anthropic.com/v1/messages")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    body = {
      model: "claude-sonnet-4-20250514",
      max_tokens: 2500,
      system: SYSTEM_PROMPT,
      messages: [
        { role: "user", content: content }
      ]
    }

    req = Net::HTTP::Post.new(uri.request_uri)
    req["x-api-key"] = api_key
    req["anthropic-version"] = "2023-06-01"
    req["Content-Type"] = "application/json"
    req.body = JSON.dump(body)

    res = http.request(req)
    raise "Claude error: #{res.code} #{res.body}" unless res.code.to_i.between?(200, 299)

    json = JSON.parse(res.body)
    json.dig("content", 0, "text")
  end

  def build_content
    parts = []
    parts << "# Error: #{@issue.exception_class}"
    parts << "Message: #{@issue.sample_message}"
    parts << "Controller action: #{@issue.controller_action}"
    parts << "Top frame: #{@issue.top_frame}"
    parts << "Occurrences: #{@issue.count}, First seen: #{@issue.first_seen_at}, Last seen: #{@issue.last_seen_at}"

    if @event
      parts << "\n## Request Context"
      parts << "Request: #{@event.request_method} #{@event.request_path}"
      parts << "Server: #{@event.server_name}" if @event.server_name.present?
      status = @event.context && (@event.context["error_status"] || @event.context[:error_status])
      parts << "Status: #{status}" if status

      # Include source code context if available (from gem 0.6+)
      if @event.has_structured_stack_trace?
        source_context = format_source_context(@event.structured_stack_trace)
        if source_context.present?
          parts << "\n## Source Code Context"
          parts << source_context
        end

        # Also include simplified call stack
        parts << "\n## Call Stack (in-app frames)"
        @event.structured_stack_trace.select { |f| f["in_app"] }.first(10).each do |frame|
          parts << "  #{frame['file']}:#{frame['line']} in `#{frame['method']}`"
        end
      else
        # Fallback for old errors without structured stack trace
        bt = Array(@event.formatted_backtrace)
        important = bt.select { |l| l.include?("/app/") || l.include?("/controllers/") || l.include?("/models/") || l.include?("/services/") }
        important = bt.first(15) if important.empty?
        parts << "\n## Backtrace"
        parts << important.join("\n")
      end

      # Request params (redacted)
      routing = @event.context && (@event.context["routing"] || @event.context[:routing])
      if routing && routing["params"]
        redacted_params = routing["params"].dup
        redacted_params.each { |k, v| redacted_params[k] = "[SCRUBBED]" if k.to_s =~ /password|token|secret|key/i }
        parts << "\n## Request Params"
        parts << redacted_params.to_json
      end
    end

    parts.join("\n")
  end

  # Format source code context from structured stack trace frames
  # Returns formatted code blocks showing the error location with surrounding context
  def format_source_context(frames)
    return nil if frames.blank?

    # Focus on in-app frames with source context (limit to first 5 for token efficiency)
    in_app_frames = frames.select do |f|
      (f["in_app"] || f[:in_app]) && (f["source_context"] || f[:source_context])
    end.first(5)

    return nil if in_app_frames.empty?

    in_app_frames.map.with_index do |frame, idx|
      ctx = frame["source_context"] || frame[:source_context]
      file = frame["file"] || frame[:file]
      line = frame["line"] || frame[:line]
      method_name = frame["method"] || frame[:method]
      frame_type = frame["frame_type"] || frame[:frame_type]

      lines = []
      lines << "### #{idx == 0 ? 'Error Location' : 'Called from'}: #{truncate_path(file)}:#{line}"
      lines << "Method: `#{method_name}` (#{frame_type})" if method_name

      lines << "```ruby"
      # Lines before the error
      (ctx["lines_before"] || ctx[:lines_before] || []).each do |l|
        lines << l
      end
      # The error line (highlighted)
      error_line = ctx["line_content"] || ctx[:line_content] || ""
      lines << ">>> #{error_line}  # <-- ERROR HERE"
      # Lines after the error
      (ctx["lines_after"] || ctx[:lines_after] || []).each do |l|
        lines << l
      end
      lines << "```"

      lines.join("\n")
    end.join("\n\n")
  end

  # Truncate long file paths for readability
  def truncate_path(path)
    return path if path.nil? || path.length <= 60
    # Keep the last meaningful part of the path
    parts = path.split("/")
    if parts.length > 3
      ".../" + parts.last(3).join("/")
    else
      path
    end
  end
end
