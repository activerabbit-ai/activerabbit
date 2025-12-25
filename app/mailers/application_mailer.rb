class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("ALERT_FROM_EMAIL")
  layout "mailer"
end
