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
  scope :last_24h, -> { where('occurred_at > ?', 24.hours.ago) }

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
      environment: payload[:environment] || 'production',
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
    'error'
  end

  private

  def set_defaults
    self.occurred_at ||= Time.current
    self.environment ||= 'production'
  end

  def self.extract_top_frame(backtrace)
    return 'unknown' if backtrace.blank?

    frames = backtrace.is_a?(Array) ? backtrace : backtrace.split("\n")

    # Find first frame that's not from gems/system
    app_frame = frames.find do |frame|
      !frame.include?('/gems/') &&
      !frame.include?('/ruby/') &&
      !frame.include?('/lib/ruby/') &&
      frame.include?('/')
    end

    app_frame || frames.first || 'unknown'
  end

  def self.extract_controller_from_backtrace(backtrace)
    return 'unknown' if backtrace.blank?

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
        'UnknownController#unknown'
      end
    else
      'BackgroundJob' # Assume background job if no controller found
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
            value = '[SCRUBBED]'
            break
          end
        end
      end
      value
    end

    scrubbed
  end
end
