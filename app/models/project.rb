class Project < ApplicationRecord
  # Multi-tenancy setup - Project belongs to Account (tenant)
  acts_as_tenant(:account)

  belongs_to :user
  has_many :issues, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :perf_rollups, dependent: :destroy
  has_many :performance_summaries, dependent: :destroy
  has_many :sql_fingerprints, dependent: :destroy
  has_many :releases, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :healthchecks, dependent: :destroy
  has_many :alert_rules, dependent: :destroy
  has_many :alert_notifications, dependent: :destroy
  has_many :deploys, dependent: :destroy
  has_many :notification_preferences, dependent: :destroy

  validates :name, presence: true
  validates_uniqueness_to_tenant :name, scope: :user_id
  validates :slug, presence: true, uniqueness: true
  validates :environment, presence: true
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL" }

  before_validation :generate_slug, if: -> { slug.nil? && name.present? }

  scope :active, -> { where(active: true) }

  def generate_api_token!
    api_tokens.create!(
      name: "Default Token",
      token: SecureRandom.hex(32),
      active: true
    )
  end

  def api_token
    api_tokens.active.first&.token
  end

  def create_default_alert_rules!
    # Create default alert rules for new projects
    alert_rules.create!([
      {
        name: "High Error Frequency",
        rule_type: "error_frequency",
        threshold_value: 10,
        time_window_minutes: 5,
        cooldown_minutes: 30,
        enabled: true
      },
      {
        name: "Slow Response Time",
        rule_type: "performance_regression",
        threshold_value: 2000, # 2 seconds
        time_window_minutes: 1,
        cooldown_minutes: 15,
        enabled: true
      },
      {
        name: "N+1 Query Detection",
        rule_type: "n_plus_one",
        threshold_value: 1, # Alert on any high-severity N+1
        time_window_minutes: 1,
        cooldown_minutes: 60,
        enabled: true
      },
      {
        name: "New Issues",
        rule_type: "new_issue",
        threshold_value: 1,
        time_window_minutes: 1,
        cooldown_minutes: 0, # No cooldown for new issues
        enabled: true
      }
    ])
  end

  # Computed health status used for UI:
  # - If an explicit health_status has been set (via uptime checks), use it.
  # - Otherwise, if we have seen at least one issue or event for this project,
  #   treat it as "healthy" instead of "unknown".
  def computed_health_status
    return health_status if health_status.present?

    if issues.exists? || events.exists?
      "healthy"
    else
      "unknown"
    end
  end

  def update_health_status!(healthcheck_results)
    critical_count = healthcheck_results.count { |r| r[:status] == "critical" }
    warning_count = healthcheck_results.count { |r| r[:status] == "warning" }

    new_status = if critical_count > 0
                   "critical"
    elsif warning_count > 0
                   "warning"
    else
                   "healthy"
    end

    update!(health_status: new_status)
  end

  # ---- Notifications ----
  def slack_configured?
    slack_access_token.present?
  end

  def notifications_enabled?
    settings.dig("notifications", "enabled") != false
  end

  def notify_via_slack?
    return false unless notifications_enabled?
    return false unless slack_configured?

    settings.dig("notifications", "channels", "slack") == true
  end

  def notify_via_email?
    return false unless notifications_enabled?

    settings.dig("notifications", "channels", "email") == true
  end

  def notification_pref_for(alert_type)
    notification_preferences.find_by(alert_type: alert_type)
  end

  def self.ransackable_attributes(auth_object = nil)
    ["account_id", "active", "created_at", "description",
    "environment", "health_status", "id", "id_value", "last_event_at",
    "name", "settings", "slug", "tech_stack", "updated_at", "url", "user_id"]
  end

  private

  def generate_slug
    base_slug = name.parameterize
    counter = 1
    potential_slug = base_slug

    while Project.exists?(slug: potential_slug)
      potential_slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = potential_slug
  end
end
