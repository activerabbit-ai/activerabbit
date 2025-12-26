class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("ALERT_FROM_EMAIL", "ActiveRabbit <activerabbit@updates.activerabbit.ai>")

  layout "mailer"
end
