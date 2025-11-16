class Deploy < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :project
  belongs_to :release
  belongs_to :user, optional: true

  has_many :events, dependent: :nullify
  has_many :issues, dependent: :nullify

  validates :started_at, presence: true

  scope :recent, -> { order(started_at: :desc) }
  scope :for_environment, ->(env) { joins(:release).where(releases: { environment: env }) }

  def duration_seconds
    return nil unless finished_at
    finished_at - started_at
  end

  def errors_count
    events.where(level: %w[error fatal]).count
  end

  def errors_per_hour
    return 0 if duration_seconds.nil? || duration_seconds == 0
    (errors_count / (duration_seconds / 3600.0)).round(2)
  end

  def performance_summary
    release.regression_summary
  end
end
