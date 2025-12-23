class Deploy < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :project
  belongs_to :release
  belongs_to :user, optional: true

  has_many :events, dependent: :nullify

  validates :started_at, presence: true

  scope :recent, -> { order(started_at: :desc) }
  scope :for_environment, ->(env) { joins(:release).where(releases: { environment: env }) }

  def duration_seconds
    return nil unless finished_at
    finished_at - started_at
  end

  def errors_count
    Issue
      .joins(:events)
      .where(events: {
        project_id: project_id
      })
      .where("events.occurred_at >= ?", started_at)
      .distinct
      .count
  end

  def time_since_deploy_seconds
    Time.current - started_at
  end

  def errors_per_hour
    hours = time_since_deploy_seconds / 3600.0
    return 0 if hours <= 0

    (errors_count / hours).round(2)
  end

  def performance_summary
    release.regression_summary
  end

  def duration_human
    return "—" unless finished_at

    seconds = duration_seconds.to_i

    if seconds < 60
      "#{seconds}s"
    elsif seconds < 3600
      "#{seconds / 60}m"
    else
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      "#{hours}h #{minutes}m"
    end
  end
end
