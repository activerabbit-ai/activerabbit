class ApplicationMailer < ActionMailer::Base
  default from: "ActiveRabbit <#{ENV.fetch("ALERT_FROM_EMAIL")}>"
  layout "mailer"
end
