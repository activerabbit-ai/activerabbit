class SendWelcomeEmailJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 3

  def perform(user_id, reset_token)
    user = User.find(user_id)
    UserMailer.welcome_and_setup_password(user, reset_token).deliver_now
  rescue => e
    Rails.logger.error "SendWelcomeEmailJob failed: #{e.message}"
    raise e
  end
end
