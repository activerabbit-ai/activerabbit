class Issue < ApplicationRecord
  # Multi-tenancy setup - Issue belongs to Account (tenant)
  acts_as_tenant(:account)

  belongs_to :project
  has_many :events, dependent: :destroy

  validates :fingerprint, presence: true
  validates_uniqueness_to_tenant :fingerprint, scope: :project_id
  validates :exception_class, presence: true
  validates :top_frame, presence: true
  validates :controller_action, presence: true
  validates :status, inclusion: { in: %w[open wip closed] }

  scope :open, -> { where(status: "open") }
  scope :wip, -> { where(status: "wip") }
  scope :closed, -> { where(status: "closed") }
  scope :recent, -> { order(last_seen_at: :desc) }
  scope :by_frequency, -> { order(count: :desc) }

  def github_pr_url
    read_attribute(:github_pr_url).presence || project&.settings&.dig("issue_pr_urls", id.to_s)
  end

  def self.find_or_create_by_fingerprint(project:, exception_class:, top_frame:, controller_action:, sample_message: nil)
    fingerprint = generate_fingerprint(exception_class, top_frame, controller_action)

    issue = find_by(project: project, fingerprint: fingerprint)
    if issue
      # обновляем счетчик и статус
      issue.update!(
        count: issue.count + 1,
        last_seen_at: Time.current,
        status: issue.status == "closed" ? "open" : issue.status,
        closed_at: issue.status == "closed" ? nil : issue.closed_at
      )
      return issue
    end

    begin
      create!(
        project: project,
        fingerprint: fingerprint,
        exception_class: exception_class,
        top_frame: top_frame,
        controller_action: controller_action,
        sample_message: sample_message,
        count: 1,
        first_seen_at: Time.current,
        last_seen_at: Time.current,
        status: "open"
      )
    rescue ActiveRecord::RecordNotUnique
      find_by(project: project, fingerprint: fingerprint)
    end
  end

  def mark_wip!
    update!(status: "wip")
  end

  def close!
    update!(status: "closed", closed_at: Time.current)
  end

  def reopen!
    update!(status: "open", closed_at: nil)
  end

  def title
    "#{exception_class} in #{controller_action}"
  end

  def source_location
    "#{controller_action} (#{top_frame})"
  end

  def events_last_24h
    events.where("created_at > ?", 24.hours.ago).count
  end

  # Unique users affected (last 24h)
  def unique_users_affected_24h
    events.where("occurred_at > ?", 24.hours.ago)
          .where.not(user_id_hash: nil)
          .distinct
          .count(:user_id_hash)
  end

  # Most common environment
  def primary_environment
    events.where.not(environment: nil)
          .group(:environment)
          .order("count_id DESC")
          .limit(1)
          .count(:id)
          .keys
          .first || "production"
  end

  # Most recent release version
  def current_release
    events.where.not(release_version: nil)
          .order(occurred_at: :desc)
          .limit(1)
          .pluck(:release_version)
          .first || "unknown"
  end

  # Impact percentage (errors in last 24h / total requests in last 24h)
  # Note: This requires tracking total requests, which we'll estimate from all events
  def impact_percentage_24h
    return 0.0 if project.nil?

    error_count = events_last_24h
    return 0.0 if error_count.zero?

    # Get total events for the project in last 24h as a proxy for total requests
    total_events = ActsAsTenant.without_tenant do
      Event.where(project_id: project.id)
           .where("occurred_at > ?", 24.hours.ago)
           .count
    end

    return 0.0 if total_events.zero?

    ((error_count.to_f / total_events.to_f) * 100).round(2)
  end

  # Construct full URL from most recent event
  def full_url
    recent_event = events.order(occurred_at: :desc).first
    return nil unless recent_event

    # Get data from event or context
    ctx = recent_event.context || {}
    req = (ctx["request"] || ctx[:request] || {})

    host = recent_event.server_name || req["server_name"] || req[:server_name]
    port = req["server_port"] || req[:server_port]
    path = recent_event.request_path || req["request_path"] || req[:request_path]

    return nil if host.blank? || path.blank?

    # Determine scheme (https if port 443, otherwise http)
    scheme = (port.to_s == "443") ? "https" : "http"

    # Build URL
    url = "#{scheme}://#{host}"
    url += ":#{port}" if port.present? && !["80", "443"].include?(port.to_s)
    url += path
    url
  end

  def self.ransackable_attributes(auth_object = nil)
    ["account_id", "ai_summary", "ai_summary_generated_at", "closed_at",
    "controller_action", "count", "created_at", "exception_class",
    "fingerprint", "first_seen_at", "id", "id_value", "last_seen_at",
    "project_id", "sample_message", "status", "top_frame", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["account", "events", "project"]
  end

  private

  # Exception classes that should be grouped more aggressively
  # These are "noise" errors where the specific code location doesn't matter much
  COARSE_FINGERPRINT_EXCEPTIONS = %w[
    ActiveRecord::RecordNotFound
    ActionController::RoutingError
    ActionController::UnknownFormat
    ActionController::InvalidAuthenticityToken
    ActionController::ParameterMissing
  ].freeze

  def self.generate_fingerprint(exception_class, top_frame, controller_action)
    # Normalize top frame (remove line numbers, normalize paths)
    normalized_frame = top_frame.gsub(/:\d+/, ":N").gsub(/\/\d+\//, "/N/")

    # For common "noise" exceptions, use coarse fingerprinting:
    # Group by exception_class + controller#action (ignore specific code location/line)
    # This ensures ONE issue per action, ONE notification per action per rate limit period
    # Example: 10,000 RecordNotFound from CompaniesController#show → 1 issue → 1 notification
    if COARSE_FINGERPRINT_EXCEPTIONS.include?(exception_class)
      components = [
        exception_class,
        controller_action # Full controller#action for per-action grouping
      ].compact
    else
      # Standard fingerprinting for other errors
      components = [
        exception_class,
        normalized_frame,
        controller_action
      ].compact
    end

    Digest::SHA256.hexdigest(components.join("|"))
  end
end
