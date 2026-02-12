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

  # Human-readable explanation for common exception types (140-200 chars)
  # Technical but accessible — clear for developers, understandable for technical managers
  def error_explanation(exception_class)
    explanations = {
      # Ruby Core Errors
      "SystemStackError" => "Infinite recursion — a method keeps calling itself without an exit condition, exhausting the call stack. Check for circular method calls.",
      "NoMethodError" => "Called a method on nil or an object that doesn't respond to it. Usually means a variable is nil when it shouldn't be.",
      "NameError" => "Referenced an undefined variable or constant. Check for typos or missing requires/imports.",
      "ArgumentError" => "Method received wrong number or type of arguments. Verify the method signature matches how it's being called.",
      "TypeError" => "Operation on incompatible types — like concatenating String with Integer. Add proper type conversion.",
      "ZeroDivisionError" => "Division by zero attempted. Add a guard clause to check the divisor before dividing.",
      "RuntimeError" => "Generic runtime error raised explicitly in code. Check the message for context on what failed.",
      "LoadError" => "Required file or gem not found. Verify it's in Gemfile and properly installed, or check the file path.",
      "SyntaxError" => "Ruby syntax is invalid — missing end, bracket, or quote. Check the file referenced in the trace.",
      "RangeError" => "Numeric value out of valid range — like invalid date components or array index overflow.",
      "IOError" => "File I/O operation failed — file may be closed, locked, or inaccessible.",
      "Errno::ENOENT" => "File or directory not found. Verify the path exists and is accessible by the application.",
      "Errno::EACCES" => "Permission denied on file or directory. Check filesystem permissions for the app user.",
      "Errno::ECONNREFUSED" => "Connection refused by target host. The service is down or not accepting connections on that port.",
      "Timeout::Error" => "Operation exceeded time limit. External service may be slow — consider increasing timeout or adding retry logic.",
      "Net::ReadTimeout" => "HTTP read timed out waiting for server response. The remote endpoint is slow or unresponsive.",
      "Net::OpenTimeout" => "HTTP connection couldn't be established in time. Check network connectivity and target host availability.",

      # ActiveJob Errors
      "ActiveJob::DeserializationError" => "Job arguments reference a record that no longer exists. The record was likely deleted between when the job was enqueued and when it ran.",

      # ActiveRecord Errors
      "ActiveRecord::RecordNotFound" => "No record found with the given ID or conditions. Use find_by (returns nil) instead of find, or rescue the exception.",
      "ActiveRecord::RecordInvalid" => "Model validation failed on save! or create!. Check model validations and the data being submitted.",
      "ActiveRecord::RecordNotUnique" => "Unique constraint violated — duplicate value in a column with unique index. Handle race conditions or validate uniqueness first.",
      "ActiveRecord::StatementInvalid" => "Invalid SQL executed — column doesn't exist, syntax error, or constraint violation. Check the query and schema.",
      "ActiveRecord::ConnectionNotEstablished" => "No database connection. Database server may be down, credentials wrong, or connection pool exhausted.",
      "ActiveRecord::NoDatabaseError" => "Database doesn't exist. Run rails db:create or check DATABASE_URL configuration.",
      "ActiveRecord::PendingMigrationError" => "Migrations haven't been run. Execute rails db:migrate to update the schema.",
      "ActiveRecord::AssociationTypeMismatch" => "Wrong model type assigned to association — expected one class, got another. Check the assignment.",

      # ActionController Errors
      "ActionController::RoutingError" => "No route matches this URL/HTTP method. Check routes.rb or the URL being requested.",
      "ActionController::ParameterMissing" => "Required parameter missing in params. Ensure the form/API sends the expected nested parameter structure.",
      "ActionController::UnpermittedParameters" => "Params contain keys not in permit list. Update strong parameters to allow needed fields.",
      "ActionController::InvalidAuthenticityToken" => "CSRF token invalid or missing. Session may have expired, or form is missing authenticity_token.",
      "ActionController::UnknownFormat" => "No handler for requested format (HTML, JSON, etc). Add respond_to block or check Accept header.",

      # ActionView Errors
      "ActionView::MissingTemplate" => "Template file not found. Verify view exists at expected path with correct format and handler extension.",
      "ActionView::Template::Error" => "Error while rendering template — often nil reference in view. Check the line number in the template.",

      # Other Common Errors
      "JSON::ParserError" => "Invalid JSON syntax — malformed payload or unexpected characters. Validate JSON structure before parsing.",
      "Redis::CannotConnectError" => "Redis connection failed. Server may be down or REDIS_URL misconfigured.",
      "Rack::Timeout::RequestTimeoutException" => "Request exceeded timeout limit. Slow query or external call blocking the response — optimize or move to background job.",
      "JWT::DecodeError" => "JWT token couldn't be decoded — malformed, wrong algorithm, or invalid secret/key.",
      "JWT::ExpiredSignature" => "JWT token expired. Client needs to refresh or re-authenticate.",
      "OpenSSL::SSL::SSLError" => "SSL/TLS handshake failed — certificate invalid, expired, or protocol mismatch.",
      "Faraday::ConnectionFailed" => "HTTP request couldn't connect to host. Service down or network unreachable.",
      "Faraday::TimeoutError" => "HTTP request timed out. External API is slow — consider retry with backoff.",
      "SocketError" => "Socket/DNS error — hostname couldn't be resolved. Check the URL and network configuration.",
      "Pundit::NotAuthorizedError" => "Authorization failed — user doesn't have permission. Check policy rules for this action.",
      "CanCan::AccessDenied" => "CanCanCan authorization denied. User lacks required ability — check Ability definitions.",
      "Stripe::InvalidRequestError" => "Stripe API rejected the request — invalid parameters or missing required fields.",
      "Stripe::CardError" => "Card was declined. Customer should verify card details or try a different payment method.",
      "PG::UniqueViolation" => "PostgreSQL unique constraint violated. Duplicate value in unique column — handle at application level.",
      "PG::ForeignKeyViolation" => "PostgreSQL foreign key constraint failed. Referenced record missing or trying to delete parent with children.",
      "PG::UndefinedTable" => "Table doesn't exist in database. Run migrations or check table name spelling.",
      "PG::UndefinedColumn" => "Column doesn't exist in table. Run migrations or verify column name in query.",
      "Sidekiq::Shutdown" => "Job interrupted by Sidekiq shutdown. Will be retried automatically on restart.",
      "Sidekiq::JobRetry::Handled" => "Job failed and Sidekiq's retry mechanism caught it. Check the original error in the cause chain for the root issue.",
      "PG::ConnectionBad" => "PostgreSQL connection lost or couldn't be established. Database may be down, overloaded, or connection pool exhausted.",
      "Redis::TimeoutError" => "Redis operation timed out. Server may be overloaded, slow query, or network latency issue.",
      "Redis::CommandError" => "Redis rejected the command — wrong data type, memory limit, or invalid arguments. Check the Redis operation.",
      "Net::SMTPAuthenticationError" => "SMTP authentication failed. Email credentials are wrong or the mail server rejected the login.",
      "ActiveRecord::ConnectionTimeoutError" => "Couldn't get a database connection from the pool in time. All connections are busy — increase pool size or optimize slow queries.",
      "SignalException" => "Process received termination signal (SIGTERM/SIGKILL). Normal during deploys — jobs should be idempotent.",
      "Interrupt" => "Process interrupted (SIGINT/Ctrl+C). Expected in development, investigate if happening in production.",
      "StandardError" => "Base exception class — check the specific error message and backtrace for details."
    }

    explanations[exception_class] || explanations[exception_class.to_s.split("::").last]
  end
end
