class Event < ApplicationRecord
  belongs_to :project
  belongs_to :issue, optional: true
  belongs_to :release, optional: true

  validates :event_type, inclusion: { in: %w[error performance] }
  validates :fingerprint, presence: true
  validates :occurred_at, presence: true

  scope :errors, -> { where(event_type: 'error') }
  scope :performance, -> { where(event_type: 'performance') }
  scope :recent, -> { order(occurred_at: :desc) }
  scope :for_timerange, ->(start_time, end_time) { where(occurred_at: start_time..end_time) }

  before_create :set_defaults

  def self.ingest_error(project:, payload:)
    fingerprint = generate_error_fingerprint(payload)

    # Find or create issue
    issue = Issue.find_or_create_by_fingerprint(
      project: project,
      fingerprint: fingerprint,
      attributes: {
        exception_type: payload[:exception_type],
        message: payload[:message],
        controller_action: payload[:controller_action],
        request_path: payload[:request_path]
      }
    )

    # Create event
    create!(
      project: project,
      issue: issue,
      event_type: 'error',
      fingerprint: fingerprint,
      payload: scrub_pii(payload),
      occurred_at: payload[:occurred_at] || Time.current,
      environment: payload[:environment],
      release_version: payload[:release_version],
      user_id_hash: payload[:user_id] ? Digest::SHA256.hexdigest(payload[:user_id].to_s) : nil
    )
  end

  def self.ingest_performance(project:, payload:)
    fingerprint = generate_performance_fingerprint(payload)

    create!(
      project: project,
      event_type: 'performance',
      fingerprint: fingerprint,
      payload: scrub_pii(payload),
      occurred_at: payload[:occurred_at] || Time.current,
      environment: payload[:environment],
      release_version: payload[:release_version],
      duration_ms: payload[:duration_ms],
      controller_action: payload[:controller_action],
      request_path: payload[:request_path],
      sql_queries_count: payload[:sql_queries_count],
      n_plus_one_detected: payload[:n_plus_one_detected] || false
    )
  end

  private

  def set_defaults
    self.occurred_at ||= Time.current
    self.environment ||= 'production'
  end

  def self.generate_error_fingerprint(payload)
    components = [
      payload[:exception_type],
      payload[:message]&.gsub(/\d+/, 'N')&.gsub(/[a-f0-9]{8,}/, 'HEX'), # Normalize numbers and hex
      payload[:controller_action] || payload[:request_path]&.gsub(/\/\d+/, '/N') # Normalize IDs in paths
    ].compact

    Digest::SHA256.hexdigest(components.join('|'))
  end

  def self.generate_performance_fingerprint(payload)
    components = [
      payload[:controller_action] || payload[:request_path]&.gsub(/\/\d+/, '/N'),
      payload[:environment]
    ].compact

    Digest::SHA256.hexdigest(components.join('|'))
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
