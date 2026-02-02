class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def github
    handle_auth "GitHub", "github"
  end

  def google_oauth2
    handle_auth "Google", "google_oauth2"
  end

  def handle_auth(kind, provider)
    auth = request.env["omniauth.auth"]

    # Check if this is a "link account" request (user already signed in)
    if user_signed_in? && session[:link_provider]
      session.delete(:link_provider)
      link_provider_to_current_user(auth, kind, provider)
      return
    end

    @user = User.from_omniauth(auth)

    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: kind) if is_navigational_format?
    else
      session["devise.#{kind.downcase}_data"] = auth.except(:extra)

      error_message = @user.errors.full_messages.to_sentence

      if error_message.include?("Email has already been taken")
        error_message = "A user with this email is already registered. Please sign in with your password and connect your #{kind} account in settings."
      elsif error_message.include?("Email can't be blank") || error_message.include?("Email is invalid")
        error_message = "We couldn't retrieve your email from #{kind}. Please add a verified email to your #{kind} account, or sign up with email and password instead."
      end

      redirect_to new_user_registration_url, alert: error_message
    end
  end

  private

  def link_provider_to_current_user(auth, kind, provider)
    # Check if this OAuth account is already linked to another user
    existing_user = User.find_by(provider: auth.provider, uid: auth.uid)
    
    if existing_user && existing_user != current_user
      redirect_to edit_user_path(current_user), alert: "This #{kind} account is already linked to another user."
      return
    end

    # Check if current user already has a different provider linked
    if current_user.provider.present? && current_user.provider != provider
      redirect_to edit_user_path(current_user), alert: "You already have #{current_user.provider == 'google_oauth2' ? 'Google' : 'GitHub'} connected. Disconnect it first to connect #{kind}."
      return
    end

    # Link the provider to current user
    if current_user.update(provider: auth.provider, uid: auth.uid)
      redirect_to edit_user_path(current_user), notice: "#{kind} account connected successfully!"
    else
      redirect_to edit_user_path(current_user), alert: "Failed to connect #{kind} account."
    end
  end
end
