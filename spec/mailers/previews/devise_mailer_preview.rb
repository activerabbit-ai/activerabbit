# Preview Devise emails at http://localhost:3000/rails/mailers/devise_mailer
class DeviseMailerPreview < ActionMailer::Preview
  # Preview confirmation email
  def confirmation_instructions
    user = User.first || User.new(email: "test@example.com")
    token = user.confirmation_token || "sample_token_123"
    Devise::Mailer.confirmation_instructions(user, token)
  end

  # Preview reset password email
  def reset_password_instructions
    user = User.first || User.new(email: "test@example.com")
    token = "sample_reset_token_123"
    Devise::Mailer.reset_password_instructions(user, token)
  end
end
