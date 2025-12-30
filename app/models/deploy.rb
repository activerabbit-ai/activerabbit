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
    Event
      .where(project_id: project_id)
      .where("occurred_at >= ?", started_at)
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

  def errors_last_hour
    Event
      .where(project_id: project_id)
      .where("occurred_at >= ?", 1.hour.ago)
      .count
  end

  def errors_per_hour
    from = [started_at, 1.hour.ago].max

    Event
      .where(project_id: project_id)
      .where("occurred_at >= ?", from)
      .count
  end

  def performance_summary
    release.regression_summary
  end
end
