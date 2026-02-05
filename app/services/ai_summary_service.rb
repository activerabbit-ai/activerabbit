class AiSummaryService
  # Maximum number of files that can be auto-fixed in a single PR (safety limit)
  # Additional file suggestions will be shown to user for manual review
  MAX_FILES_PER_FIX = 1

  SYSTEM_PROMPT = <<~PROMPT
    You are a senior Rails debugging assistant. Analyze the error and provide a PRECISE, ACTIONABLE fix.

    Use this EXACT format with proper line breaks:

    ## Root Cause

    Brief explanation (2-3 sentences).

    ## Suggested Fix

    ### File 1: `app/path/to/file.rb`
    **Line:** 42

    **Before:**

    ```ruby
    # The exact broken code (copy from context)
    broken_code_line_1
    broken_code_line_2
    ```

    **After:**

    ```ruby
    # The fixed code (ready to apply)
    fixed_code_line_1
    fixed_code_line_2
    ```

    ### File 2: `app/path/to/another_file.rb` (if needed)
    **Line:** 15

    **Before:**

    ```ruby
    old_code
    ```

    **After:**

    ```ruby
    new_code
    ```

    ## Prevention

    Brief tips (1-2 bullet points).

    CRITICAL RULES:
    1. The "Before" code MUST match the EXACT code from the file (same indentation, same variable names)
    2. The "After" code MUST be a drop-in replacement (same indentation level)
    3. Include enough context lines (3-5 lines) so the fix can be located precisely
    4. Always specify the exact file path and line number
    5. You MUST have a blank line before each ``` code fence
    6. Focus on fixing the PRIMARY error file only (where the exception occurred)
    7. If other files also need changes, add a "## Related Changes" section listing them with brief descriptions - these will be shown as suggestions for the user to fix locally before creating the PR
  PROMPT

  def initialize(issue:, sample_event: nil, github_client: nil)
    @issue = issue
    @event = sample_event
    @github_client = github_client
    @project = issue.project
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
      model: "claude-opus-4-20250514",
      max_tokens: 5000,
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

    error_file_path = nil
    error_line_number = nil
    error_file_content = nil

    if @event
      parts << "\n## Request Context"
      parts << "Request: #{@event.request_method} #{@event.request_path}"
      parts << "Server: #{@event.server_name}" if @event.server_name.present?
      status = @event.context && (@event.context["error_status"] || @event.context[:error_status])
      parts << "Status: #{status}" if status

      # Include source code context if available (from gem 0.6+)
      if @event.has_structured_stack_trace?
        # Extract error file info
        error_frame = @event.structured_stack_trace.find { |f| f["in_app"] || f[:in_app] }
        if error_frame
          error_file_path = normalize_file_path(error_frame["file"] || error_frame[:file])
          error_line_number = error_frame["line"] || error_frame[:line]

          # Collect source code for class extraction (from SDK)
          ctx = error_frame["source_context"] || error_frame[:source_context]
          if ctx
            error_file_content = [
              ctx["lines_before"] || ctx[:lines_before] || [],
              ctx["line_content"] || ctx[:line_content],
              ctx["lines_after"] || ctx[:lines_after] || []
            ].flatten.compact.join("\n")
          end
        end

        # Try to fetch FULL error file from GitHub for complete context
        full_file_fetched = false
        if @github_client && error_file_path.present?
          full_file = fetch_full_error_file(error_file_path, error_line_number)
          if full_file.present?
            parts << "\n## ERROR FILE (FULL CONTEXT)"
            parts << "**File:** `#{error_file_path}`"
            parts << "**Error Line:** #{error_line_number}"
            parts << ""
            parts << "```ruby"
            parts << full_file
            parts << "```"
            full_file_fetched = true
            Rails.logger.info "[AiSummaryService] Fetched full error file from GitHub: #{error_file_path}"
          end
        end

        # Fallback to SDK snippet if GitHub fetch failed
        unless full_file_fetched
          source_context = format_source_context(@event.structured_stack_trace)
          if source_context.present?
            parts << "\n## Source Code Context (SDK snippet)"
            parts << source_context
          end
        end

        # Include simplified call stack
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

    # Fetch related files from GitHub for better context
    if @github_client && error_file_path.present?
      related_context = fetch_related_files_for_analysis(error_file_path, error_file_content)
      if related_context.present?
        parts << "\n## Related Codebase Files"
        parts << related_context
      end
    end

    parts.join("\n")
  end

  # Fetch the full error file from GitHub with line numbers
  def fetch_full_error_file(file_path, error_line)
    return nil unless @github_client && @project&.github_repo_full_name.present?

    owner, repo = @project.github_repo_full_name.split("/")
    return nil unless owner && repo

    content = fetch_github_file(owner, repo, file_path)
    return nil unless content.present?

    lines = content.lines

    # Add line numbers, marking the error line
    lines.map.with_index(1) do |line, num|
      marker = num == error_line ? " >>> " : "     "
      "#{num.to_s.rjust(4)}#{marker}#{line}"
    end.join
  rescue => e
    Rails.logger.warn "[AiSummaryService] Failed to fetch full error file: #{e.message}"
    nil
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

  # Normalize file path to Rails conventional paths
  def normalize_file_path(path)
    return nil if path.blank?
    path = path.sub(%r{^\./}, "")
    path = path.sub(%r{^.*/app/}, "app/")
    path = path.sub(%r{^.*/lib/}, "lib/")
    path = path.sub(%r{^.*/config/}, "config/")
    if path.start_with?("/")
      match = path.match(%r{/(app|lib|config|spec|test)/.*$})
      path = match[0].sub(%r{^/}, "") if match
    end
    path.presence
  end

  # Fetch related files from GitHub for better AI analysis context
  def fetch_related_files_for_analysis(error_file_path, error_file_content)
    return nil unless @github_client && @project&.github_repo_full_name.present?

    owner, repo = @project.github_repo_full_name.split("/")
    return nil unless owner && repo

    files_to_fetch = []
    fetched_files = []

    # Extract class names from error file content
    referenced_classes = extract_referenced_classes(error_file_content || "")
    Rails.logger.info "[AiSummaryService] Referenced classes: #{referenced_classes.join(', ')}"

    # Determine related files based on error file type
    if error_file_path&.include?("/controllers/")
      controller_name = File.basename(error_file_path, ".rb").sub(/_controller$/, "")
      model_name = controller_name.singularize
      files_to_fetch << "app/models/#{model_name}.rb"

      referenced_classes.each do |klass|
        files_to_fetch << "app/services/#{klass.underscore}.rb" if klass.end_with?("Service")
      end

    elsif error_file_path&.include?("/models/")
      referenced_classes.each do |klass|
        files_to_fetch << "app/models/#{klass.underscore}.rb"
      end

    elsif error_file_path&.include?("/services/")
      referenced_classes.each do |klass|
        if klass.end_with?("Service")
          files_to_fetch << "app/services/#{klass.underscore}.rb"
        else
          files_to_fetch << "app/models/#{klass.underscore}.rb"
        end
      end

    elsif error_file_path&.include?("/jobs/")
      referenced_classes.each do |klass|
        if klass.end_with?("Service")
          files_to_fetch << "app/services/#{klass.underscore}.rb"
        else
          files_to_fetch << "app/models/#{klass.underscore}.rb"
        end
      end
    end

    # Check for schema if database-related error
    if @issue.exception_class.to_s.include?("ActiveRecord") ||
       @issue.sample_message.to_s.downcase.include?("column") ||
       @issue.sample_message.to_s.downcase.include?("table")
      files_to_fetch << "db/schema.rb"
    end

    # Dedupe and limit
    files_to_fetch = files_to_fetch.uniq.reject { |f| f == error_file_path }.first(4)

    # Fetch each file
    files_to_fetch.each do |file_path|
      content = fetch_github_file(owner, repo, file_path)
      if content
        # Truncate to 80 lines for token efficiency
        lines = content.lines
        truncated = lines.first(80).join
        truncated += "\n# ... (#{lines.size - 80} more lines)" if lines.size > 80
        fetched_files << { path: file_path, content: truncated }
        Rails.logger.info "[AiSummaryService] Fetched related file: #{file_path} (#{lines.size} lines)"
      end
    end

    return nil if fetched_files.empty?

    # Build context string
    fetched_files.map do |file|
      "### #{file[:path]}\n```ruby\n#{file[:content]}\n```"
    end.join("\n\n")
  rescue => e
    Rails.logger.warn "[AiSummaryService] Failed to fetch related files: #{e.message}"
    nil
  end

  # Extract class names referenced in Ruby code
  def extract_referenced_classes(content)
    classes = []

    # Match class references
    content.scan(/\b([A-Z][a-zA-Z0-9]+)(?:\.|::|\s)/).each { |m| classes << m[0] }

    # Match associations
    content.scan(/(?:belongs_to|has_one|has_many|has_and_belongs_to_many)\s+:(\w+)/).each do |m|
      classes << m[0].classify
    end

    # Filter common non-model classes
    excluded = %w[Rails ActiveRecord ActionController ApplicationController ApplicationRecord
                  String Integer Float Array Hash Time DateTime Date File Logger JSON
                  Thread Mutex Queue ENV Kernel Object Class Module Base Error]

    classes.uniq.reject { |c| excluded.include?(c) || c.length < 3 }
  end

  # Fetch a single file from GitHub
  def fetch_github_file(owner, repo, file_path)
    file_url = "/repos/#{owner}/#{repo}/contents/#{file_path}"
    response = @github_client.get(file_url)
    return nil unless response.is_a?(Hash) && response["content"]

    Base64.decode64(response["content"])
  rescue => e
    Rails.logger.debug "[AiSummaryService] Could not fetch #{file_path}: #{e.message}"
    nil
  end
end
