class Deploy < ApplicationRecord
  acts_as_tenant(:account)

  belongs_to :project
  belongs_to :release
  belongs_to :user, optional: true

  has_many :events, dependent: :nullify

  validates :started_at, presence: true

  scope :recent, -> { order(started_at: :desc) }
  scope :for_environment, ->(env) { joins(:release).where(releases: { environment: env }) }

  def errors_count
    Issue
      .joins(:events)
      .where(events: {
        project_id: project_id
      })
      .where("events.occurred_at >= ?", started_at)
      .count
  end

  def live_for_seconds(next_deploy = nil)
    end_time =
      if next_deploy
        next_deploy.started_at
      else
        Time.current
      end

    (end_time - started_at).to_i
  end

  def errors_per_hour(next_deploy = nil)
    seconds = live_for_seconds(next_deploy)
    hours = seconds / 3600.0
    return 0 if hours <= 0

    (errors_count / hours).round(2)
  end

  def performance_summary
    release.regression_summary
  end
end
