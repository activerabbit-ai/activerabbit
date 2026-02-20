class Users::RegistrationsController < Devise::RegistrationsController
  protected

  def after_sign_up_path_for(resource)
    flash[:notice] = "Welcome to ActiveRabbit! Your 14-day free trial has started — enjoy full access to all features."
    super
  end

  def after_inactive_sign_up_path_for(resource)
    flash[:notice] = "Welcome to ActiveRabbit! Your 14-day free trial has started. Please check your email to confirm your account."
    super
  end
end
