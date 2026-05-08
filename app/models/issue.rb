class Issue < ApplicationRecord
  # Multi-tenancy setup - Issue belongs to Account (tenant)
  acts_as_tenant(:account)

  belongs_to :project
  has_many :events, dependent: :destroy
  has_many :replays

  validates :fingerprint, presence: true
  validates_uniqueness_to_tenant :fingerprint, scope: :project_id
  validates :exception_class, presence: true
  validates :top_frame, presence: true
  validates :controller_action, presence: true
  validates :status, inclusion: { in: %w[open wip closed] }
  validates :severity, inclusion: { in: %w[low medium high critical] }, allow_nil: true

  SEVERITIES = %w[low medium high critical].freeze

  AUTO_FIX_STATUSES = %w[
    creating_pr
    pr_created
    pr_created_review_needed
    ci_pending
    ci_passed
    ci_failed
    ci_timeout
    merged
    merge_failed
    failed
    monitor_error
    skipped_low_confidence
    skipped_capped
    skipped_no_github
    skipped_no_analysis
  ].freeze

  validates :auto_fix_status, inclusion: { in: AUTO_FIX_STATUSES }, allow_nil: true

  # severity_score = impact + frequency + business + regression + data_risk - mitigation
  # Score 0-100 → mapped to severity level
  SEVERITY_SCORE_THRESHOLDS = { critical: 80, high: 55, medium: 25 }.freeze

  # A. Impact — exception classes that signal app crashes / total failures
  CRASH_EXCEPTION_CLASSES = %w[
    SecurityError SystemStackError NoMemoryError SignalException SystemExit
    fatal Errno::ENOMEM
    PG::ConnectionBad Mysql2::Error::ConnectionError
    Redis::CannotConnectError Redis::TimeoutError
    OpenSSL::SSL::SSLError
  ].freeze

  INTERNAL_ERROR_CLASSES = %w[
    NoMethodError TypeError NameError ArgumentError RuntimeError
    ActiveRecord::StatementInvalid ActiveRecord::Deadlocked
    ActiveRecord::LockWaitTimeout
    Net::ReadTimeout Net::OpenTimeout Timeout::Error
    Errno::ECONNREFUSED Errno::ECONNRESET
    Stripe::CardError Stripe::InvalidRequestError Stripe::APIConnectionError
    Stripe::APIError Stripe::AuthenticationError
  ].freeze

  PARTIAL_BREAK_CLASSES = %w[
    ActiveRecord::RecordNotFound ActiveRecord::RecordInvalid
    ActiveRecord::RecordNotUnique
    ActionController::UnknownFormat
    ActionController::ParameterMissing
    JSON::ParserError Encoding::UndefinedConversionError
  ].freeze

  COSMETIC_CLASSES = %w[
    ActionController::RoutingError
    ActionController::InvalidAuthenticityToken
    ActionDispatch::Http::MimeNegotiation::InvalidType
  ].freeze

  # C. Business — controller patterns by criticality
  CHECKOUT_PATTERNS  = %w[checkout payment subscription charge billing invoice stripe order purchase cart].freeze
  AUTH_PATTERNS      = %w[session login signin signup register password auth omniauth devise].freeze
  CORE_PATTERNS      = %w[dashboard home main app api].freeze
  ADMIN_PATTERNS     = %w[admin super_admin sidekiq administrate].freeze
  INTERNAL_PATTERNS  = %w[health_check test_monitoring debug internal up].freeze

  # D. Data risk — exception classes that signal data/security/money risk
  SECURITY_RISK_CLASSES = %w[
    SecurityError OpenSSL::SSL::SSLError
    ActionController::InvalidAuthenticityToken
    JWT::DecodeError JWT::VerificationError
  ].freeze

  DATA_CORRUPTION_CLASSES = %w[
    ActiveRecord::StatementInvalid ActiveRecord::Deadlocked
    ActiveRecord::SerializationFailure
    PG::UniqueViolation PG::ForeignKeyViolation PG::NotNullViolation
    Encoding::UndefinedConversionError
  ].freeze

  scope :open, -> { where(status: "open") }
  scope :wip, -> { where(status: "wip") }
  scope :closed, -> { where(status: "closed") }
  scope :frontend, -> { where(source: "frontend") }
  scope :backend, -> { where(source: "backend") }
  scope :recent, -> { order(last_seen_at: :desc) }
  scope :by_frequency, -> { order(count: :desc) }
  scope :by_severity, ->(level) { where(severity: level) }
  scope :critical, -> { where(severity: "critical") }
  scope :high_and_above, -> { where(severity: %w[high critical]) }
  scope :severity_ordered, -> {
    order(Arel.sql("CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 ELSE 4 END, last_seen_at DESC"))
  }
  # Fast job-failure filter using the denormalized boolean flag on issues.
  # Falls back to the expensive Event subquery only if the column hasn't been migrated yet.
  scope :from_job_failures, -> {
    if column_names.include?("is_job_failure")
      where(is_job_failure: true)
    else
      where(id: Event.from_job_failures.distinct.select(:issue_id))
    end
  }

  before_save :detect_job_failure
  before_save :calculate_severity!

  def github_pr_url
    read_attribute(:github_pr_url).presence || project&.settings&.dig("issue_pr_urls", id.to_s)
  end

  def self.find_or_create_by_fingerprint(project:, exception_class:, top_frame:, controller_action:, sample_message: nil, source: "backend")
    fingerprint = generate_fingerprint(exception_class, top_frame, controller_action)

    issue = find_by(project: project, fingerprint: fingerprint)
    if issue
      # Atomic SQL increment — prevents lost updates when multiple Sidekiq
      # workers process the same fingerprint concurrently.
      # Ruby-level `count + 1` is a read-then-write race condition.
      Issue.where(id: issue.id).update_all(
        ["count = count + 1, last_seen_at = ?, " \
         "status = CASE WHEN status = 'closed' THEN 'open' ELSE status END, " \
         "closed_at = CASE WHEN status = 'closed' THEN NULL ELSE closed_at END",
         Time.current]
      )
      issue.reload
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
        source: source,
        count: 1,
        first_seen_at: Time.current,
        last_seen_at: Time.current,
        status: "open"
      )
    rescue ActiveRecord::RecordNotUnique
      # Another worker created the issue between our find_by and create!
      # Find it AND atomically increment (the old code just returned without
      # incrementing — the event was invisible in the count).
      issue = find_by(project: project, fingerprint: fingerprint)
      if issue
        Issue.where(id: issue.id).update_all(
          ["count = count + 1, last_seen_at = ?, " \
           "status = CASE WHEN status = 'closed' THEN 'open' ELSE status END, " \
           "closed_at = CASE WHEN status = 'closed' THEN NULL ELSE closed_at END",
           Time.current]
        )
        issue.reload
      end
      issue
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

  def calculated_severity
    score = severity_score
    if score >= SEVERITY_SCORE_THRESHOLDS[:critical]
      "critical"
    elsif score >= SEVERITY_SCORE_THRESHOLDS[:high]
      "high"
    elsif score >= SEVERITY_SCORE_THRESHOLDS[:medium]
      "medium"
    else
      "low"
    end
  end

  def severity_score_breakdown
    {
      impact: impact_score,
      frequency: frequency_score,
      business: business_score,
      regression: regression_score,
      data_risk: data_risk_score,
      mitigation: mitigation_score,
      total: severity_score
    }
  end

  def severity_score
    raw = impact_score + frequency_score + business_score +
          regression_score + data_risk_score - mitigation_score
    raw.clamp(0, 100)
  end

  def update_severity!
    new_severity = calculated_severity
    update_column(:severity, new_severity) if severity != new_severity
    new_severity
  end

  # Severity badge helpers for UI
  def severity_color
    case severity
    when "critical" then "red"
    when "high" then "orange"
    when "medium" then "yellow"
    else "gray"
    end
  end

  def severity_icon
    case severity
    when "critical" then "🔴"
    when "high" then "🟠"
    when "medium" then "🟡"
    else "⚪"
    end
  end

  def source_location
    "#{controller_action} (#{top_frame})"
  end

  def auto_fix_in_progress?
    %w[creating_pr pr_created pr_created_review_needed ci_pending ci_passed].include?(auto_fix_status)
  end

  def auto_fix_completed?
    auto_fix_status == "merged"
  end

  def auto_fix_failed?
    %w[failed ci_failed ci_timeout merge_failed monitor_error].include?(auto_fix_status)
  end

  def auto_fix_eligible?
    auto_fix_status.nil? && status == "open" && ai_summary.present?
  end

  def events_last_24h
    events.where("occurred_at > ?", 24.hours.ago).count
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

  # Sort by impact (24h event count). Used for "Impact %" column sorting.
  # Index: events(issue_id, occurred_at) — used by the correlated subquery when this ransacker is used.
  # For better scale, ErrorsController#index uses a single aggregated subquery + LEFT JOIN when sorting by this.
  ransacker :events_24h_count do
    Arel.sql("(SELECT COUNT(*)::integer FROM events WHERE events.issue_id = issues.id AND events.occurred_at > (NOW() - INTERVAL '24 hours'))")
  end

  # Sort by whether issue has a PR (1 = has PR URL in project settings, 0 = not). Used for "PR" column sorting.
  # One projects PK lookup per row; projects is small — fine at scale.
  ransacker :has_pr_url do
    Arel.sql("(SELECT CASE WHEN (p.settings->'issue_pr_urls'->(issues.id::text)) IS NOT NULL AND (p.settings->'issue_pr_urls'->(issues.id::text))::text != 'null' THEN 1 ELSE 0 END FROM projects p WHERE p.id = issues.project_id)")
  end

  # Sort severity as Critical (0) → High (1) → Medium (2) → Low (3). Used for "Severity" column sorting.
  # In-row expression only — no extra I/O; index on severity can be used for filter, not for this sort expression.
  ransacker :severity_order do
    Arel.sql("CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 ELSE 4 END")
  end

  def self.ransackable_attributes(auth_object = nil)
    ["account_id", "ai_summary", "ai_summary_generated_at", "closed_at",
    "controller_action", "count", "created_at", "exception_class",
    "events_24h_count", "fingerprint", "first_seen_at", "has_pr_url", "id", "id_value", "last_seen_at",
    "project_id", "sample_message", "severity", "severity_order", "source", "status", "top_frame", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["account", "events", "project"]
  end

  private

  # Auto-detect whether this issue comes from a background job.
  # Workers / job classes don't follow the "SomeController#action" pattern.
  def detect_job_failure
    return unless respond_to?(:is_job_failure) && has_attribute?(:is_job_failure)
    return unless controller_action_changed? || new_record?

    self.is_job_failure = controller_action.present? && !controller_action.include?("Controller#")
  end

  def job_failure?
    if has_attribute?(:is_job_failure)
      is_job_failure?
    else
      controller_action.present? && !controller_action.to_s.include?("Controller#")
    end
  end

  def calculate_severity!
    return unless has_attribute?(:severity)
    return unless count_changed? || new_record? || severity.nil?

    self.severity = calculated_severity
  end

  # ── A. Impact Score (max ~35) ──────────────────────────────────────
  # How much does it break?
  def impact_score
    klass = exception_class.to_s

    if CRASH_EXCEPTION_CLASSES.any? { |c| klass.include?(c) }
      35 # App completely crashes / infra down
    elsif INTERNAL_ERROR_CLASSES.any? { |c| klass.include?(c) }
      25 # Request fails with 500
    elsif job_failure?
      8  # Background job failed (may auto-retry)
    elsif PARTIAL_BREAK_CLASSES.any? { |c| klass.include?(c) }
      15 # Page partly broken but usable
    elsif COSMETIC_CLASSES.any? { |c| klass.include?(c) }
      5  # Cosmetic / routing noise
    else
      20 # Unknown exception → assume moderate impact
    end
  end

  # ── B. Frequency Score (max ~50) ───────────────────────────────────
  # Events per hour + unique user percentage
  def frequency_score
    events_per_hour_score + unique_users_percentage_score
  end

  # ── C. Business Score (max ~30) ────────────────────────────────────
  # Where does it happen? (checkout, auth, core, admin, internal)
  def business_score
    action = controller_action.to_s.downcase

    if CHECKOUT_PATTERNS.any? { |p| action.include?(p) }
      30
    elsif AUTH_PATTERNS.any? { |p| action.include?(p) }
      25
    elsif CORE_PATTERNS.any? { |p| action.include?(p) }
      20
    elsif ADMIN_PATTERNS.any? { |p| action.include?(p) }
      8
    elsif INTERNAL_PATTERNS.any? { |p| action.include?(p) }
      2
    else
      12 # Regular feature — moderate business value
    end
  end

  # ── D. Regression Score (max ~25) ──────────────────────────────────
  # Did this appear after a deploy or reappear after being fixed?
  def regression_score
    score = 0

    # Reappeared after previously fixed (+25)
    if closed_at.present? && status != "closed"
      score += 25
    elsif first_appeared_in_latest_release?
      score += 20 # First seen in latest release, potential deploy regression
    end

    score
  end

  # ── E. Data Risk Score (max ~40) ───────────────────────────────────
  # Does it risk money, data, or security?
  def data_risk_score
    klass = exception_class.to_s
    action = controller_action.to_s.downcase
    score = 0

    # Security / privacy risk
    if SECURITY_RISK_CLASSES.any? { |c| klass.include?(c) }
      score += 40
    end

    # Data corruption risk
    if DATA_CORRUPTION_CLASSES.any? { |c| klass.include?(c) }
      score += 35
    end

    # Billing / payment risk (exception in checkout/payment area)
    if CHECKOUT_PATTERNS.any? { |p| action.include?(p) } &&
       !COSMETIC_CLASSES.any? { |c| klass.include?(c) }
      score += 30
    end

    # Cap at 40 to keep within overall balance
    [score, 40].min
  end

  # ── F. Mitigation Score (subtracted, max ~20) ─────────────────────
  # Reduce severity if the error is less harmful than it looks
  def mitigation_score
    score = 0

    # Background job that likely auto-retries
    if job_failure?
      score += 10
    end

    # Only internal / admin users affected
    action = controller_action.to_s.downcase
    if ADMIN_PATTERNS.any? { |p| action.include?(p) } ||
       INTERNAL_PATTERNS.any? { |p| action.include?(p) }
      score += 10
    end

    # Very few users affected → low blast radius
    if unique_users_affected_24h <= 1 && events_last_24h <= 2
      score += 8
    end

    # Cap at 20 so mitigation cannot fully erase a real issue
    [score, 20].min
  end

  # ── Frequency sub-scores ───────────────────────────────────────────

  def events_per_hour_score
    now = Time.current
    last_hour = events.where(occurred_at: (now - 1.hour)..now).count

    if last_hour >= 1000 then 25
    elsif last_hour >= 100 then 18
    elsif last_hour >= 10  then 10
    elsif last_hour >= 1   then 4
    else 0
    end
  end

  def unique_users_percentage_score
    return 0 if project.nil?

    users_1h = events.where("occurred_at > ?", 1.hour.ago)
                     .where.not(user_id_hash: nil)
                     .distinct.count(:user_id_hash)
    return 0 if users_1h == 0

    total_users_1h = ActsAsTenant.without_tenant do
      Event.where(project_id: project.id)
           .where("occurred_at > ?", 1.hour.ago)
           .where.not(user_id_hash: nil)
           .distinct.count(:user_id_hash)
    end
    return 0 if total_users_1h == 0

    pct = (users_1h.to_f / total_users_1h * 100)

    if pct >= 20.0 then 25
    elsif pct >= 5.0 then 15
    elsif pct >= 1.0 then 8
    else 0
    end
  end

  def first_appeared_in_latest_release?
    return false unless first_seen_at && project

    latest_release = project.releases.recent.first
    return false unless latest_release&.deployed_at

    first_seen_at >= latest_release.deployed_at &&
      first_seen_at <= latest_release.deployed_at + 2.hours
  end

  # Exception classes that should be grouped by originating code location
  # These are common errors where the controller action is just the entry point,
  # but the real bug lives in shared code (base controllers, concerns, etc.)
  ORIGIN_BASED_FINGERPRINT_EXCEPTIONS = %w[
    ActiveRecord::RecordNotFound
    ActionController::RoutingError
    ActionController::UnknownFormat
    ActionController::InvalidAuthenticityToken
    ActionController::ParameterMissing
  ].freeze

  def self.generate_fingerprint(exception_class, top_frame, controller_action)
    # Normalize top frame (remove line numbers, normalize paths)
    normalized_frame = top_frame.gsub(/:\d+/, ":N").gsub(/\/\d+\//, "/N/")

    # For common exceptions, group by exception_class + originating code location (top_frame)
    # This groups errors that come from the same code path, regardless of entry point
    # Example: RecordNotFound from base_controller.rb#authenticate_with_bearer_token
    #          called via HoursController#index, TasksController#index, etc.
    #          → ALL grouped into 1 issue (same root cause, single fix needed)
    if ORIGIN_BASED_FINGERPRINT_EXCEPTIONS.include?(exception_class)
      components = [
        exception_class,
        normalized_frame # Group by originating code location, not entry point
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
