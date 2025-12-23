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

  def live_for_seconds
    Time.current - started_at
  end

  def errors_per_hour
    hours = live_for_seconds / 3600.0
    return 0 if hours <= 0

    (errors_count / hours).round(2)
  end

  def performance_summary
    release.regression_summary
  end

  def live_for_human
    seconds = (Time.current - started_at).to_i
    return "just now" if seconds < 60

    minutes = seconds / 60
    return "#{minutes}m" if minutes < 60

    hours = minutes / 60
    return "#{hours}h" if hours < 24

    days = hours / 24
    return "#{days}d" if days < 7

    weeks = days / 7
    remaining_days = days % 7

    if remaining_days.zero?
      "#{weeks}w"
    else
      "#{weeks}w #{remaining_days}d"
    end
  end
end
