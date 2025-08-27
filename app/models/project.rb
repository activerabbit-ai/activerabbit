class Project < ApplicationRecord
  # Multi-tenancy setup - Project belongs to Account (tenant)
  acts_as_tenant(:account)

  belongs_to :user
  has_many :issues, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :perf_rollups, dependent: :destroy
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

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  scope :active, -> { where(active: true) }

  def generate_api_token!
    api_tokens.create!(
      name: "Default Token",
      token: SecureRandom.hex(32),
      active: true
    )
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
    critical_count = healthcheck_results.count { |r| r[:status] == 'critical' }
    warning_count = healthcheck_results.count { |r| r[:status] == 'warning' }

    new_status = if critical_count > 0
                   'critical'
                 elsif warning_count > 0
                   'warning'
                 else
                   'healthy'
                 end

    update!(health_status: new_status)
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
