class UserMailer < ApplicationMailer
  def welcome_and_setup_password(user, reset_token)
    @user = user
    @password_reset_url = edit_user_password_url(reset_password_token: reset_token)

    mail(
      to: user.email,
      subject: 'Welcome to Active Rabbit - Setup Your Password'
    )
  end
end
