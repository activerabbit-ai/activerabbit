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

  def self.check_error_frequency_rules(issue)
    issue.project.alert_rules.active.for_type("error_frequency").each do |rule|
      recent_count = issue.events
        .where("created_at > ?", rule.time_window_minutes.minutes.ago)
        .count

      if recent_count >= rule.threshold_value
        AlertJob.perform_async(
          rule.id,
          "error_frequency",
          {
            issue_id: issue.id,
            count: recent_count,
            time_window: rule.time_window_minutes
          }
        )
      end
    end
  end

  def self.check_performance_rules(event)
    event.project.alert_rules.active.for_type("performance_regression").each do |rule|
      next unless event.duration_ms && event.duration_ms >= rule.threshold_value

      target = event.target.presence || "unknown"

      recent_alert = AlertNotification
        .where(alert_rule: rule)
        .where("created_at > ?", rule.time_window_minutes.minutes.ago)
        .where("payload ->> 'target' = ?", target)
        .exists?

      next if recent_alert

      AlertJob.perform_async(
        rule.id,
        "performance_regression",
        {
          event_id: event.id,
          duration_ms: event.duration_ms,
          target: target
        }
      )
    end
  end

  def self.check_n_plus_one_rules(project, incidents)
    project.alert_rules.active.for_type("n_plus_one").each do |rule|
      high_severity = incidents.select { |i| i[:severity] == "high" }

      if high_severity.size >= rule.threshold_value
        AlertJob.perform_async(
          rule.id,
          "n_plus_one",
          {
            incidents: high_severity,
            controller_action: incidents.first[:controller_action]
          }
        )
      end
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
