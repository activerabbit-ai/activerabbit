module ErrorsHelper
  # Parse a single backtrace line into structured data
  # Example input: "app/controllers/resumes_controller.rb:101:in `import_from_pdf'"
  # Returns: { file: "app/controllers/resumes_controller.rb", line: 101, method: "import_from_pdf", in_app: true }
  def parse_backtrace_frame(frame)
    return nil if frame.blank?

    # If frame is already a hash (from client's structured_stack_trace), normalize it
    if frame.is_a?(Hash)
      return normalize_client_frame(frame)
    end

    # Match patterns like:
    # app/controllers/foo.rb:25:in `method_name'
    # /path/to/gems/some_gem/lib/file.rb:10:in `block in method'
    # app/models/user.rb:15:in `<class:User>'
    pattern = /^(.+?):(\d+):in [`'](.+?)'?\s*$/

    if match = frame.match(pattern)
      file = match[1]
      line = match[2].to_i
      method_name = match[3]

      {
        file: file,
        line: line,
        method: method_name,
        raw: frame,
        in_app: in_app_frame?(file),
        frame_type: classify_frame(file),
        source_context: nil # Will be filled from client data if available
      }
    else
      # Fallback for non-standard formats
      {
        file: nil,
        line: nil,
        method: nil,
        raw: frame,
        in_app: false,
        frame_type: :unknown,
        source_context: nil
      }
    end
  end

  # Normalize a frame hash from client's structured_stack_trace
  def normalize_client_frame(frame)
    # Handle both string and symbol keys
    file = frame["file"] || frame[:file]
    line = frame["line"] || frame[:line]
    method_name = frame["method"] || frame[:method]
    raw = frame["raw"] || frame[:raw]
    in_app = frame["in_app"] || frame[:in_app]
    frame_type = (frame["frame_type"] || frame[:frame_type])&.to_sym || classify_frame(file)
    source_context = frame["source_context"] || frame[:source_context]

    {
      file: file,
      line: line&.to_i,
      method: method_name,
      raw: raw || "#{file}:#{line}:in `#{method_name}'",
      in_app: in_app,
      frame_type: frame_type,
      source_context: normalize_source_context(source_context)
    }
  end

  # Normalize source context from client
  def normalize_source_context(ctx)
    return nil if ctx.blank?

    lines_before = ctx["lines_before"] || ctx[:lines_before] || []
    line_content = ctx["line_content"] || ctx[:line_content]
    lines_after = ctx["lines_after"] || ctx[:lines_after] || []
    start_line = ctx["start_line"] || ctx[:start_line]

    return nil if line_content.blank?

    # Convert lines_before to expected format
    formatted_before = lines_before.each_with_index.map do |content, idx|
      { number: start_line + idx, content: content.to_s }
    end

    # Main error line
    formatted_line = {
      number: start_line + lines_before.length,
      content: line_content.to_s
    }

    # Lines after
    formatted_after = lines_after.each_with_index.map do |content, idx|
      { number: start_line + lines_before.length + 1 + idx, content: content.to_s }
    end

    {
      lines_before: formatted_before,
      line_content: formatted_line,
      lines_after: formatted_after,
      start_line: start_line,
      file_exists: true
    }
  end

  # Parse entire backtrace - prefers client's structured_stack_trace if available
  def parse_backtrace(backtrace_or_event)
    # If we got an Event object, try to get structured data from client first
    if backtrace_or_event.respond_to?(:structured_stack_trace)
      structured = backtrace_or_event.structured_stack_trace
      if structured.present? && structured.is_a?(Array) && structured.any?
        return structured.map { |frame| normalize_client_frame(frame) }.compact
      end
      # Fallback to raw backtrace
      backtrace_or_event = backtrace_or_event.formatted_backtrace
    end

    return [] if backtrace_or_event.blank?

    frames = backtrace_or_event.is_a?(Array) ? backtrace_or_event : backtrace_or_event.split("\n")
    frames.map { |frame| parse_backtrace_frame(frame) }.compact
  end

  # Determine if a frame is "in app" code (not gem/system)
  def in_app_frame?(file)
    return false if file.blank?

    # In-app if it starts with app/, lib/, or doesn't have /gems/ or /ruby/ paths
    file.start_with?("app/") ||
      file.start_with?("lib/") ||
      file.include?("/app/") && !file.include?("/gems/") ||
      (!file.include?("/gems/") && !file.include?("/ruby/") && !file.include?("/rubygems/"))
  end

  # Classify frame type for badge display
  def classify_frame(file)
    return :unknown if file.blank?

    case file
    when /controllers/
      :controller
    when /models/
      :model
    when /services/
      :service
    when /jobs/
      :job
    when /views/
      :view
    when /helpers/
      :helper
    when /mailers/
      :mailer
    when /concerns/
      :concern
    when /lib\//
      :library
    when /gems?[\/\\]/
      :gem
    else
      :other
    end
  end

  # Get frame type badge color
  def frame_type_badge_class(frame_type)
    case frame_type
    when :controller
      "bg-blue-100 text-blue-800"
    when :model
      "bg-green-100 text-green-800"
    when :service
      "bg-purple-100 text-purple-800"
    when :job
      "bg-orange-100 text-orange-800"
    when :view
      "bg-pink-100 text-pink-800"
    when :gem
      "bg-gray-100 text-gray-600"
    else
      "bg-gray-100 text-gray-700"
    end
  end

  # Get frame type label
  def frame_type_label(frame_type)
    case frame_type
    when :controller then "Controller"
    when :model then "Model"
    when :service then "Service"
    when :job then "Job"
    when :view then "View"
    when :helper then "Helper"
    when :mailer then "Mailer"
    when :concern then "Concern"
    when :library then "Lib"
    when :gem then "Gem"
    else nil
    end
  end

  # Get source context - from client data if available, otherwise returns nil
  # (Server doesn't have access to client source files)
  def read_source_context(file_path_or_frame, line_number = nil, context_lines: 5)
    # If we got a frame hash with source_context from client, use it
    if file_path_or_frame.is_a?(Hash)
      return file_path_or_frame[:source_context]
    end

    # Server cannot read client source files, so return nil
    # The client gem should have sent source context in structured_stack_trace
    nil
  end

  # Get language for syntax highlighting based on file extension
  def source_language(file_path)
    return "ruby" if file_path.blank?

    ext = File.extname(file_path.to_s).downcase
    case ext
    when ".rb" then "ruby"
    when ".erb" then "erb"
    when ".js" then "javascript"
    when ".ts" then "typescript"
    when ".jsx" then "jsx"
    when ".tsx" then "tsx"
    when ".html" then "html"
    when ".css" then "css"
    when ".scss" then "scss"
    when ".yml", ".yaml" then "yaml"
    when ".json" then "json"
    else "ruby"
    end
  end

  # Truncate file path for display, keeping the important parts
  def truncate_file_path(file_path, max_parts: 4)
    return file_path if file_path.blank?

    parts = file_path.to_s.split("/")
    return file_path if parts.length <= max_parts

    # Keep first and last parts
    ".../" + parts.last(max_parts).join("/")
  end

  # Extract method name for display (clean up block notation)
  def clean_method_name(method_name)
    return "unknown" if method_name.blank?

    # Clean up common Ruby patterns
    method_name
      .gsub(/^block \(\d+ levels?\) in /, "")
      .gsub(/^block in /, "")
      .gsub(/^rescue in /, "")
      .gsub(/^ensure in /, "")
      .gsub(/<[^>]+>/, "")  # Remove <class:Foo>, <module:Bar>, etc.
      .strip
      .presence || method_name
  end

  # Group frames by in_app status for better display
  def group_frames_by_context(frames)
    return [] if frames.blank?

    groups = []
    current_group = { in_app: frames.first&.dig(:in_app), frames: [] }

    frames.each do |frame|
      if frame[:in_app] == current_group[:in_app]
        current_group[:frames] << frame
      else
        groups << current_group if current_group[:frames].any?
        current_group = { in_app: frame[:in_app], frames: [frame] }
      end
    end

    groups << current_group if current_group[:frames].any?
    groups
  end

  # Find the "culprit" frame - first in-app frame
  def find_culprit_frame(frames)
    frames.find { |f| f[:in_app] }
  end
end
