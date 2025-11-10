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

  validates :name, presence: true
  validates_uniqueness_to_tenant :name, scope: :user_id
  validates :slug, presence: true, uniqueness: true
  validates :environment, presence: true
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL" }

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

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

  # Slack notification settings
  def slack_webhook_url
    # Priority: ENV variable > database setting
    env_webhook = ENV["SLACK_WEBHOOK_URL_#{slug.upcase}"] || ENV["SLACK_WEBHOOK_URL"]
    env_webhook.presence || settings["slack_webhook_url"]
  end

  def slack_webhook_url=(url)
    # Only store in database if not using environment variable
    if url.present? && !url.start_with?("ENV:")
      self.settings = settings.merge("slack_webhook_url" => url&.strip)
    elsif url&.start_with?("ENV:")
      # Store reference to environment variable
      env_var = url.sub("ENV:", "")
      self.settings = settings.merge("slack_webhook_url" => "ENV:#{env_var}")
    else
      # Clear the setting
      new_settings = settings.dup
      new_settings.delete("slack_webhook_url")
      self.settings = new_settings
    end
  end

  def slack_webhook_from_env?
    settings["slack_webhook_url"]&.start_with?("ENV:") ||
    ENV["SLACK_WEBHOOK_URL_#{slug.upcase}"].present? ||
    ENV["SLACK_WEBHOOK_URL"].present?
  end

  def slack_channel
    settings["slack_channel"] || "#alerts"
  end

  def slack_channel=(channel)
    # Ensure channel starts with # if it's not a user DM
    formatted_channel = channel&.strip
    if formatted_channel.present? && !formatted_channel.start_with?("#", "@")
      formatted_channel = "##{formatted_channel}"
    end
    self.settings = settings.merge("slack_channel" => formatted_channel)
  end

  def slack_configured?
    slack_webhook_url.present?
  end

  def slack_notifications_enabled?
    slack_configured? && settings["slack_notifications_enabled"] != false
  end

  def enable_slack_notifications!
    self.settings = settings.merge("slack_notifications_enabled" => true)
    save!
  end

  def disable_slack_notifications!
    self.settings = settings.merge("slack_notifications_enabled" => false)
    save!
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
