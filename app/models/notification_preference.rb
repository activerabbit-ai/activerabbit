class NotificationPreference < ApplicationRecord
  belongs_to :project

  ALERT_TYPES = %w[
    error_frequency
    performance_regression
    n_plus_one
    new_issue
  ]

  # Frequency options control PER-FINGERPRINT rate limiting (Sentry/AppSignal style)
  # - immediate: Notify for each new fingerprint (5 min minimum between same fingerprint)
  # - every_30_minutes: Max once per 30 min for same error fingerprint
  # - every_2_hours: Max once per 2 hours for same error fingerprint
  # - first_in_deploy: Only notify on first occurrence since latest deploy
  # - after_close: Only notify when a previously-closed issue recurs
  FREQUENCIES = %w[
    immediate
    every_30_minutes
    every_2_hours
    first_in_deploy
    after_close
  ]

  validates :alert_type, inclusion: { in: ALERT_TYPES }
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :project_id, uniqueness: { scope: :alert_type }

  # Convert frequency to minutes for rate limiting
  # Used by IssueAlertJob for per-fingerprint rate limiting
  def rate_limit_minutes
    case frequency
    when "immediate"
      5   # Minimum 5 min even for "immediate" to prevent spam
    when "every_30_minutes"
      30
    when "every_2_hours"
      120
    else
      30  # Default
    end
  end

  # Check if notification can be sent (used for global throttling if needed)
  # Note: Per-fingerprint rate limiting is handled separately in IssueAlertJob
  def can_send_now?
    return false unless enabled

    case frequency
    when "immediate"
      true
    when "every_30_minutes"
      last_sent_at.nil? || last_sent_at < 30.minutes.ago
    when "every_2_hours"
      last_sent_at.nil? || last_sent_at < 2.hours.ago
    when "first_in_deploy"
      true  # Logic handled in IssueAlertJob
    when "after_close"
      true  # Logic handled in IssueAlertJob
    else
      true
    end
  end

  def mark_sent!
    update!(last_sent_at: Time.current)
  end

  # Human-readable description of the frequency setting
  def frequency_description
    case frequency
    when "immediate"
      "Notify immediately (max once per 5 min per error)"
    when "every_30_minutes"
      "Max once per 30 minutes per error"
    when "every_2_hours"
      "Max once per 2 hours per error"
    when "first_in_deploy"
      "Only first occurrence after each deploy"
    when "after_close"
      "Only when resolved issues recur"
    else
      frequency.humanize
    end
  end
end
