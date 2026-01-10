class Event < ApplicationRecord
  # Multi-tenancy setup - Event belongs to Account (tenant)
  acts_as_tenant(:account)

  belongs_to :project
  belongs_to :issue
  belongs_to :release, optional: true

  validates :occurred_at, presence: true
  validates :exception_class, presence: true
  validates :message, presence: true

  scope :recent, -> { order(occurred_at: :desc) }
  scope :for_timerange, ->(start_time, end_time) { where(occurred_at: start_time..end_time) }
  scope :last_24h, -> { where("occurred_at > ?", 24.hours.ago) }

  before_create :set_defaults

  def self.ingest_error(project:, payload:)
    # Extract exception details
    exception_class = payload[:exception_class] || payload[:exception_type]
    message = payload[:message]
    raw_backtrace = payload[:backtrace] || []
    frames = raw_backtrace.is_a?(Array) ? raw_backtrace : raw_backtrace.to_s.split("\n")

    serialized_backtrace = frames.to_json

    top_frame = extract_top_frame(frames)
    controller_action =
      payload[:controller_action] || extract_controller_from_backtrace(frames)

    # Find or create issue (grouped problem)
    issue = Issue.find_or_create_by_fingerprint(
      project: project,
      exception_class: exception_class,
      top_frame: top_frame,
      controller_action: controller_action,
      sample_message: message
    )

    # Create event (individual occurrence)
    create!(
      project: project,
      issue: issue,
      exception_class: exception_class,
      message: message,
      backtrace: serialized_backtrace,
      controller_action: controller_action,
      request_path: payload[:request_path],
      request_method: payload[:request_method],
      occurred_at: payload[:occurred_at] || Time.current,
      environment: payload[:environment] || "production",
      release_version: payload[:release_version],
      user_id_hash: payload[:user_id] ? Digest::SHA256.hexdigest(payload[:user_id].to_s) : nil,
      context: scrub_pii(payload[:context] || {}),
      server_name: payload[:server_name],
      request_id: payload[:request_id]
    )
  end

  def top_frame
    return nil if backtrace.blank?
    backtrace.is_a?(Array) ? backtrace.first : backtrace.split("\n").first
  end

  def formatted_backtrace
    return [] if backtrace.blank?
    backtrace.is_a?(Array) ? backtrace : backtrace.split("\n")
  end

  def event_type
    # For now, all events are error events
    # This could be extended in the future to support performance events, etc.
    "error"
  end

  def duration_ms
    # Error events don't typically have durations
    # This could be extended in the future to support performance events with durations
    nil
  end

  def parsed_backtrace
    return [] if backtrace.blank?

    JSON.parse(backtrace)
  rescue JSON::ParserError
    backtrace.to_s.split("\n")
  end

  def stack_frames
    lines = parsed_backtrace
    return [] unless lines.is_a?(Array)

    lines.map { |line| self.class.parse_frame_line(line) }.compact
  end

  def in_app_frames
    stack_frames.select { |f| f[:in_app] }
  end

  def relevant_frames
    frames = in_app_frames
    frames = stack_frames.first(12) if frames.empty?
    frames.first(12)
  end

  def full_frames
    stack_frames
  end

  class << self
    # Tries to parse typical Ruby backtrace formats:
    # "/path/file.rb:123:in `method'"
    # "file.rb:123:in `method'"
    def parse_frame_line(line)
      return if line.blank?

      s = line.to_s

      # file:line:in `method'
      if (m = s.match(/\A(.+?):(\d+)(?::in [`']([^`']+)[`'])?\z/))
        file = m[1]
        lineno = m[2].to_i
        func = m[3]

        {
          raw: s,
          filename: file,
          lineno: lineno,
          function: func,
          in_app: in_app_path?(file),
          library: library_from_path(file)
        }
      else
        # fallback: unknown format, keep raw
        {
          raw: s,
          filename: nil,
          lineno: nil,
          function: nil,
          in_app: false,
          library: nil
        }
      end
    end

    def in_app_path?(path)
      p = path.to_s
      return false if p.include?("/gems/") || p.include?("/lib/ruby/") || p.include?("/ruby/")
      p.include?("/app/")
    end

    def library_from_path(path)
      p = path.to_s
      return "gems" if p.include?("/gems/")
      return "ruby" if p.include?("/lib/ruby/") || p.include?("/ruby/")
      return "app"  if in_app_path?(p)
      nil
    end
  end

  def extract_repo_path(abs_path)
    # /Users/mac/Desktop/app-server/app/controllers/foo.rb
    idx = abs_path.index("/app/")
    return nil unless idx
    abs_path[idx + 1..] # => app/controllers/foo.rb
  end

  def github_source_context(frame, radius: 3)
    return nil unless release_version.present?
    return nil unless frame[:filename] && frame[:lineno]

    repo_path = extract_repo_path(frame[:filename])
    return nil unless repo_path

    file = Rails.cache.fetch(
      ["github-source", project.id, release_version, repo_path],
      expires_in: 30.minutes
    ) do
      Github::SourceFetcher
        .new(project: project, sha: release_version)
        .fetch(repo_path)
    end

    lines = Base64.decode64(file.content).lines
    idx = frame[:lineno] - 1
    return nil unless lines[idx]

    {
      pre:  lines[(idx - radius)...idx] || [],
      line: lines[idx],
      post: lines[(idx + 1)..(idx + radius)] || []
    }
  rescue Octokit::TooManyRequests => e
    Rails.logger.warn("GitHub rate limit hit")
    nil
  rescue StandardError => e
    Rails.logger.warn("GitHub source fetch failed: #{e.class} #{e.message}")
    nil
  end

  private

  def set_defaults
    self.occurred_at ||= Time.current
    self.environment ||= "production"
  end

  def self.extract_top_frame(backtrace)
    return "unknown" if backtrace.blank?

    frames = backtrace.is_a?(Array) ? backtrace : backtrace.split("\n")

    # Find first frame that's not from gems/system
    app_frame = frames.find do |frame|
      !frame.include?("/gems/") &&
      !frame.include?("/ruby/") &&
      !frame.include?("/lib/ruby/") &&
      frame.include?("/")
    end

    app_frame || frames.first || "unknown"
  end

  def self.extract_controller_from_backtrace(backtrace)
    return "unknown" if backtrace.blank?

    frames = backtrace.is_a?(Array) ? backtrace : backtrace.split("\n")

    # Look for controller patterns
    controller_frame = frames.find do |frame|
      frame.match?(/controllers\/.*_controller\.rb/) ||
      frame.match?(/app\/controllers\//)
    end

    if controller_frame
      # Extract controller#action pattern
      if match = controller_frame.match(/([a-z_]+)_controller\.rb.*in `([a-z_]+)'/)
        "#{match[1].camelize}Controller##{match[2]}"
      else
        "UnknownController#unknown"
      end
    else
      "BackgroundJob" # Assume background job if no controller found
    end
  end

  def self.scrub_pii(payload)
    return payload unless payload.is_a?(Hash)

    scrubbed = payload.deep_dup

    # Common PII fields to scrub
    pii_fields = %w[email password token secret key ssn phone credit_card]

    scrubbed.deep_transform_values! do |value|
      if value.is_a?(String)
        pii_fields.each do |field|
          if value.match?(/#{field}/i)
            value = "[SCRUBBED]"
            break
          end
        end
      end
      value
    end

    scrubbed
  end
end
