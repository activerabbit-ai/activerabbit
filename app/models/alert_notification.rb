class AlertNotification < ApplicationRecord
  belongs_to :alert_rule
  belongs_to :project

  validates :notification_type, inclusion: { in: %w[slack email webhook] }
  validates :status, inclusion: { in: %w[pending sent failed] }

  scope :recent, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(status: status) }
  scope :by_type, ->(type) { where(notification_type: type) }

  def mark_sent!
    update!(status: 'sent', sent_at: Time.current)
  end

  def mark_failed!(error_message = nil)
    update!(
      status: 'failed',
      error_message: error_message,
      failed_at: Time.current
    )
  end

  def retry!
    update!(status: 'pending', error_message: nil, failed_at: nil)
    AlertJob.perform_async(alert_rule.id, rule_type, payload)
  end
end
