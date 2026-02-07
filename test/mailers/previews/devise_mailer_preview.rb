# Preview Devise emails at http://localhost:3000/rails/mailers/devise/mailer
class Devise::MailerPreview < ActionMailer::Preview
  # Preview confirmation instructions email
  # http://localhost:3000/rails/mailers/devise/mailer/confirmation_instructions
  def confirmation_instructions
    user = User.first || User.new(email: "preview@example.com")
    Devise::Mailer.confirmation_instructions(user, "fake-token-123")
  end

  # Preview reset password instructions email
  # http://localhost:3000/rails/mailers/devise/mailer/reset_password_instructions
  def reset_password_instructions
    user = User.first || User.new(email: "preview@example.com")
    Devise::Mailer.reset_password_instructions(user, "fake-token-123")
  end

  # Preview unlock instructions email
  # http://localhost:3000/rails/mailers/devise/mailer/unlock_instructions
  def unlock_instructions
    user = User.first || User.new(email: "preview@example.com")
    Devise::Mailer.unlock_instructions(user, "fake-token-123")
  end
end
