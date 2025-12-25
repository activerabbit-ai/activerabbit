class ApplicationMailer < ActionMailer::Base
  default from: "ActiveRabbit <#{ENV.fetch("ALERT_FROM_EMAIL", "activerabbit@updates.activerabbit.ai")}>"
  layout "mailer"
end
