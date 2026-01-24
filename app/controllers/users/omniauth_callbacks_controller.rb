class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def github
    handle_auth "GitHub"
  end

  def google_oauth2
    handle_auth "Google"
  end

  def handle_auth(kind)
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: kind) if is_navigational_format?
    else
      session["devise.#{kind.downcase}_data"] = request.env["omniauth.auth"].except(:extra)

      error_message = @user.errors.full_messages.to_sentence

      if error_message.include?("Email has already been taken")
        error_message = "A user with this email is already registered. Please sign in with your password and connect your #{kind} account in settings."
      elsif error_message.include?("Email can't be blank") || error_message.include?("Email is invalid")
        error_message = "We couldn't retrieve your email from #{kind}. Please add a verified email to your #{kind} account, or sign up with email and password instead."
      end

      redirect_to new_user_registration_url, alert: error_message
    end
  end
end
