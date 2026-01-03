class NotificationPreference < ApplicationRecord
  belongs_to :project

  ALERT_TYPES = %w[
    error_frequency
    performance_regression
    n_plus_one
    new_issue
  ]

  FREQUENCIES = %w[
    immediate
    every_30_minutes
    every_2_hours
    first_in_deploy
    after_close
  ]

  validates :alert_type, inclusion: { in: ALERT_TYPES }
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :project_id, uniqueness: { scope: :alert_type }

  def can_send_now?
    return false unless enabled

    case frequency
    when "immediate"
      true
    when "every_30_minutes"
      last_sent_at.nil? || last_sent_at < 30.minutes.ago
    when "every_2_hours"
      last_sent_at.nil? || last_sent_at < 2.hours.ago
    when "first_in_deploy"
      last_sent_at.nil?
    when "after_close"
      last_sent_at.nil?
    else
      true
    end
  end

  def mark_sent!
    update!(last_sent_at: Time.current)
  end
end
