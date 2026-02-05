class ApplicationMailer < ActionMailer::Base
  DEFAULT_FROM = "ActiveRabbit <activerabbit@updates.activerabbit.ai>".freeze
  default from: DEFAULT_FROM

  layout "mailer"

  # Log all email deliveries for monitoring
  after_action :log_email_delivery

  private

  def log_email_delivery
    return unless message.to.present?

    Rails.logger.info(
      "[Email] #{self.class.name}##{action_name} " \
      "to=#{message.to.join(', ')} " \
      "subject=\"#{message.subject}\""
    )
  end
end
