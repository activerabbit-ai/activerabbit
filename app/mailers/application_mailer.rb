class ApplicationMailer < ActionMailer::Base
  DEFAULT_FROM = "ActiveRabbit <activerabbit@updates.activerabbit.ai>".freeze
  default from: DEFAULT_FROM

  layout "mailer"
end
