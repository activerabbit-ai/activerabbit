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
    backtrace = payload[:backtrace] || []
    top_frame = extract_top_frame(backtrace)
    controller_action = payload[:controller_action] || extract_controller_from_backtrace(backtrace)

    # Find or create issue (grouped problem)
    issue = Issue.find_or_create_by_fingerprint(
      project: project,
      exception_class: exception_class,
      top_frame: top_frame,
      controller_action: controller_action,
      sample_message: message
    )

    # Build context with structured stack trace (Sentry-style)
    event_context = scrub_pii(payload[:context] || {})

    # Store structured stack trace in context if provided by client
    if payload[:structured_stack_trace].present?
      event_context[:structured_stack_trace] = payload[:structured_stack_trace]
    end
    if payload[:culprit_frame].present?
      event_context[:culprit_frame] = payload[:culprit_frame]
    end

    # Create event (individual occurrence)
    create!(
      project: project,
      issue: issue,
      exception_class: exception_class,
      message: message,
      backtrace: backtrace,
      controller_action: controller_action,
      request_path: payload[:request_path],
      request_method: payload[:request_method],
      occurred_at: payload[:occurred_at] || Time.current,
      environment: payload[:environment] || "production",
      release_version: payload[:release_version],
      user_id_hash: payload[:user_id] ? Digest::SHA256.hexdigest(payload[:user_id].to_s) : nil,
      context: event_context,
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

  # Get structured stack trace with source code context (from client gem)
  # Returns array of frame hashes with: file, line, method, in_app, source_context, etc.
  def structured_stack_trace
    ctx = context || {}
    ctx["structured_stack_trace"] || ctx[:structured_stack_trace] || []
  end

  # Get the culprit frame (first in-app frame where error occurred)
  def culprit_frame
    ctx = context || {}
    ctx["culprit_frame"] || ctx[:culprit_frame]
  end

  # Check if this event has structured stack trace data from client
  def has_structured_stack_trace?
    structured_stack_trace.present?
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
