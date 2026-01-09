class PerformanceIncident < ApplicationRecord
  # Multi-tenancy setup - PerformanceIncident belongs to Account (tenant)
  acts_as_tenant(:account)

  belongs_to :project

  # Status values
  STATUSES = %w[open closed].freeze

  # Severity levels (AppSignal/Sentry style)
  SEVERITIES = %w[warning critical].freeze

  # Default thresholds (in milliseconds)
  DEFAULT_WARNING_THRESHOLD_MS = 750    # p95 > 750ms = warning
  DEFAULT_CRITICAL_THRESHOLD_MS = 1500  # p95 > 1500ms = critical

  # Warm-up period: breach must persist for N consecutive evaluations
  DEFAULT_WARMUP_COUNT = 3  # 3 consecutive minutes

  # Cooldown: don't reopen for N minutes after close
  DEFAULT_COOLDOWN_MINUTES = 10

  validates :target, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :trigger_p95_ms, presence: true, numericality: { greater_than: 0 }
  validates :threshold_ms, presence: true, numericality: { greater_than: 0 }

  scope :open, -> { where(status: "open") }
  scope :closed, -> { where(status: "closed") }
  scope :for_target, ->(target) { where(target: target) }
  scope :recent, -> { order(opened_at: :desc) }
  scope :warning, -> { where(severity: "warning") }
  scope :critical, -> { where(severity: "critical") }

  # Find or create an open incident for a target
  def self.find_open_incident(project:, target:)
    where(project: project, target: target, status: "open").first
  end

  # Evaluate p95 metrics and manage incident lifecycle
  # Called every minute by PerformanceIncidentEvaluationJob
  def self.evaluate_endpoint(project:, target:, current_p95_ms:, environment: "production")
    # Get thresholds (can be overridden per-project or per-endpoint)
    thresholds = get_thresholds(project, target)
    warning_threshold = thresholds[:warning]
    critical_threshold = thresholds[:critical]
    warmup_count = thresholds[:warmup_count]
    cooldown_minutes = thresholds[:cooldown_minutes]

    open_incident = find_open_incident(project: project, target: target)

    if current_p95_ms >= critical_threshold
      handle_breach(
        project: project,
        target: target,
        current_p95_ms: current_p95_ms,
        threshold_ms: critical_threshold,
        severity: "critical",
        warmup_count: warmup_count,
        environment: environment,
        open_incident: open_incident
      )
    elsif current_p95_ms >= warning_threshold
      handle_breach(
        project: project,
        target: target,
        current_p95_ms: current_p95_ms,
        threshold_ms: warning_threshold,
        severity: "warning",
        warmup_count: warmup_count,
        environment: environment,
        open_incident: open_incident
      )
    else
      # Below thresholds - check if we should close an open incident
      handle_recovery(
        project: project,
        target: target,
        current_p95_ms: current_p95_ms,
        warmup_count: warmup_count,
        cooldown_minutes: cooldown_minutes,
        open_incident: open_incident
      )
    end
  end

  # Get thresholds (with per-project/endpoint override support)
  def self.get_thresholds(project, target)
    # Check for per-endpoint overrides in project settings
    settings = project.settings || {}
    perf_thresholds = settings.dig("performance_thresholds") || {}
    endpoint_overrides = perf_thresholds.dig("endpoints", target) || {}

    {
      warning: (endpoint_overrides["warning_ms"] || perf_thresholds["warning_ms"] || DEFAULT_WARNING_THRESHOLD_MS).to_f,
      critical: (endpoint_overrides["critical_ms"] || perf_thresholds["critical_ms"] || DEFAULT_CRITICAL_THRESHOLD_MS).to_f,
      warmup_count: (endpoint_overrides["warmup_count"] || perf_thresholds["warmup_count"] || DEFAULT_WARMUP_COUNT).to_i,
      cooldown_minutes: (endpoint_overrides["cooldown_minutes"] || perf_thresholds["cooldown_minutes"] || DEFAULT_COOLDOWN_MINUTES).to_i
    }
  end

  # Handle threshold breach
  def self.handle_breach(project:, target:, current_p95_ms:, threshold_ms:, severity:, warmup_count:, environment:, open_incident:)
    if open_incident
      # Existing incident - update peak and potentially escalate severity
      open_incident.update!(
        peak_p95_ms: [open_incident.peak_p95_ms || 0, current_p95_ms].max,
        severity: severity_escalation(open_incident.severity, severity),
        breach_count: open_incident.breach_count + 1
      )
      return open_incident
    end

    # Check cooldown - don't reopen too soon after closing
    recent_closed = where(project: project, target: target, status: "closed")
                      .where("closed_at > ?", get_thresholds(project, target)[:cooldown_minutes].minutes.ago)
                      .exists?

    if recent_closed
      Rails.logger.debug "[PerformanceIncident] Cooldown active for #{target}, skipping"
      return nil
    end

    # Check for pending incident (warming up)
    pending_key = "perf_incident_warmup:#{project.id}:#{target}"
    redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/1")

    current_breach_count = redis.incr(pending_key)
    redis.expire(pending_key, 10.minutes.to_i) # Reset if no breach for 10 min

    if current_breach_count >= warmup_count
      # Warm-up complete - OPEN the incident
      redis.del(pending_key)

      incident = create!(
        project: project,
        target: target,
        status: "open",
        severity: severity,
        opened_at: Time.current,
        trigger_p95_ms: current_p95_ms,
        peak_p95_ms: current_p95_ms,
        threshold_ms: threshold_ms,
        breach_count: current_breach_count,
        environment: environment,
        open_notification_sent: false,
        close_notification_sent: false
      )

      # Queue OPEN notification
      PerformanceIncidentNotificationJob.perform_async(incident.id, "open")

      Rails.logger.info "[PerformanceIncident] OPENED: #{target} - p95=#{current_p95_ms}ms (threshold=#{threshold_ms}ms)"
      incident
    else
      Rails.logger.debug "[PerformanceIncident] Warming up: #{target} - #{current_breach_count}/#{warmup_count}"
      nil
    end
  end

  # Handle recovery (below threshold)
  def self.handle_recovery(project:, target:, current_p95_ms:, warmup_count:, cooldown_minutes:, open_incident:)
    # Clear any warm-up counter
    pending_key = "perf_incident_warmup:#{project.id}:#{target}"
    redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/1")
    redis.del(pending_key)

    return unless open_incident

    # Track recovery streak
    recovery_key = "perf_incident_recovery:#{project.id}:#{target}"
    recovery_count = redis.incr(recovery_key)
    redis.expire(recovery_key, 10.minutes.to_i)

    if recovery_count >= warmup_count
      # Recovery complete - CLOSE the incident
      redis.del(recovery_key)

      open_incident.update!(
        status: "closed",
        closed_at: Time.current,
        resolve_p95_ms: current_p95_ms
      )

      # Queue CLOSE notification
      PerformanceIncidentNotificationJob.perform_async(open_incident.id, "close")

      Rails.logger.info "[PerformanceIncident] CLOSED: #{target} - p95=#{current_p95_ms}ms (was #{open_incident.peak_p95_ms}ms)"
    else
      Rails.logger.debug "[PerformanceIncident] Recovering: #{target} - #{recovery_count}/#{warmup_count}"
    end
  end

  # Severity escalation (warning -> critical, never downgrade while open)
  def self.severity_escalation(current_severity, new_severity)
    return "critical" if new_severity == "critical"
    current_severity # Keep current if new is just warning
  end

  # Duration of the incident (for closed incidents)
  def duration_minutes
    return nil unless closed_at && opened_at
    ((closed_at - opened_at) / 60).round
  end

  # Human-readable status
  def status_emoji
    case status
    when "open" then severity == "critical" ? "🔴" : "🟡"
    when "closed" then "✅"
    else "❓"
    end
  end

  def title
    "#{status_emoji} #{target} - p95 #{severity == 'critical' ? 'critical' : 'degraded'}"
  end

  def summary
    if status == "open"
      "p95 latency is #{trigger_p95_ms.round(0)}ms (threshold: #{threshold_ms.round(0)}ms)"
    else
      "Resolved after #{duration_minutes} minutes. p95 recovered to #{resolve_p95_ms&.round(0) || 'N/A'}ms (peak was #{peak_p95_ms&.round(0) || 'N/A'}ms)"
    end
  end
end
