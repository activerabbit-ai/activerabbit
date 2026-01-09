class AlertRule < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :project
  has_many :alert_notifications, dependent: :destroy

  validates :name, presence: true
  validates :rule_type, inclusion: {
    in: %w[error_frequency performance_regression n_plus_one new_issue]
  }
  validates :threshold_value, presence: true, numericality: { greater_than: 0 }
  validates :time_window_minutes, presence: true, numericality: { greater_than: 0 }

  scope :active, -> { where(enabled: true) }
  scope :for_type, ->(type) { where(rule_type: type) }

  # Check error frequency rules with per-fingerprint rate limiting
  # @param issue [Issue] The issue to check
  # @param rate_limit_minutes [Integer] Rate limit from user's UI preference (NotificationPreference)
  def self.check_error_frequency_rules(issue, rate_limit_minutes: 30)
    redis = IssueAlertJob.redis  # Use shared thread-safe Redis connection

    issue.project.alert_rules.active.for_type("error_frequency").each do |rule|
      recent_count = issue.events
        .where("created_at > ?", rule.time_window_minutes.minutes.ago)
        .count

      next unless recent_count >= rule.threshold_value

      # Per-fingerprint rate limiting (AppSignal Action Interval style)
      # Rate limit is based on user's UI preference, applied per-fingerprint
      fingerprint_key = "error_freq:#{rule.id}:#{issue.fingerprint}"

      # ATOMIC check-and-set to prevent race conditions
      # SET with NX returns true only if key was set (didn't exist)
      # This prevents multiple concurrent workers from all sending alerts
      lock_acquired = redis.set(fingerprint_key, true, ex: rate_limit_minutes.minutes.to_i, nx: true)
      next unless lock_acquired

      # DB check as fallback (belt + suspenders for cases where Redis was cleared)
      recent_alert = AlertNotification
        .where(alert_rule: rule)
        .where("created_at > ?", rate_limit_minutes.minutes.ago)
        .where("payload ->> 'fingerprint' = ?", issue.fingerprint)
        .exists?

      next if recent_alert

      # Cooldown check from rule (separate from rate limit)
      if rule.cooldown_minutes.to_i > 0
        cooldown_alert = AlertNotification
          .where(alert_rule: rule)
          .where("created_at > ?", rule.cooldown_minutes.minutes.ago)
          .where("payload ->> 'fingerprint' = ?", issue.fingerprint)
          .exists?

        next if cooldown_alert
      end

      AlertJob.perform_async(
        rule.id,
        "error_frequency",
        {
          issue_id: issue.id,
          fingerprint: issue.fingerprint,
          count: recent_count,
          time_window: rule.time_window_minutes
        }
      )
    end
  end

  def self.check_performance_rules(event)
    redis = IssueAlertJob.redis

    event.project.alert_rules.active.for_type("performance_regression").each do |rule|
      next unless event.duration_ms && event.duration_ms >= rule.threshold_value

      target = event.target.presence || "unknown"
      alert_key = "#{rule.id}:#{target}"
      redis_key = "perf_alert:#{event.project_id}:#{alert_key}"

      # ATOMIC check-and-set to prevent race conditions
      ttl = [rule.time_window_minutes, rule.cooldown_minutes.to_i].max.minutes.to_i
      ttl = 5.minutes.to_i if ttl < 5.minutes.to_i  # Minimum 5 minutes
      lock_acquired = redis.set(redis_key, true, ex: ttl, nx: true)
      next unless lock_acquired

      # DB check as fallback (belt + suspenders)
      recent_alert = AlertNotification
        .where(alert_rule: rule)
        .where("created_at > ?", rule.time_window_minutes.minutes.ago)
        .where("payload ->> 'alert_key' = ?", alert_key)
        .exists?

      next if recent_alert

      AlertJob.perform_async(
        rule.id,
        "performance_regression",
        {
          event_id: event.id,
          duration_ms: event.duration_ms,
          target: target,
          alert_key: alert_key
        }
      )
    end
  end

  def self.check_n_plus_one_rules(project, incidents)
    redis = IssueAlertJob.redis

    project.alert_rules.active.for_type("n_plus_one").each do |rule|
      high_severity = incidents.select { |i| i[:severity] == "high" }
      next if high_severity.size < rule.threshold_value

      alert_key = high_severity.first[:controller_action].presence || "unknown"
      redis_key = "n1_alert:#{project.id}:#{rule.id}:#{alert_key}"

      # ATOMIC check-and-set to prevent race conditions
      ttl = [rule.time_window_minutes, rule.cooldown_minutes.to_i].max.minutes.to_i
      ttl = 5.minutes.to_i if ttl < 5.minutes.to_i  # Minimum 5 minutes
      lock_acquired = redis.set(redis_key, true, ex: ttl, nx: true)
      next unless lock_acquired

      # DB check as fallback
      recent_alert = AlertNotification
        .where(alert_rule: rule)
        .where("created_at > ?", rule.time_window_minutes.minutes.ago)
        .where("payload ->> 'controller_action' = ?", alert_key)
        .exists?

      next if recent_alert

      AlertJob.perform_async(
        rule.id,
        "n_plus_one",
        {
          incidents: high_severity,
          controller_action: alert_key
        }
      )
    end
  end

  def formatted_threshold
    case rule_type
    when "error_frequency"
      "#{threshold_value} errors in #{time_window_minutes} minutes"
    when "performance_regression"
      "Response time > #{threshold_value}ms"
    when "n_plus_one"
      "#{threshold_value} high-severity N+1 queries detected"
    when "new_issue"
      "New error types detected"
    end
  end
end
