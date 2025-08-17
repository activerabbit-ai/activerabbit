class Project < ApplicationRecord
  belongs_to :user
  has_many :issues, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :perf_rollups, dependent: :destroy
  has_many :sql_fingerprints, dependent: :destroy
  has_many :releases, dependent: :destroy
  has_many :api_tokens, dependent: :destroy
  has_many :healthchecks, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :user_id }
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
