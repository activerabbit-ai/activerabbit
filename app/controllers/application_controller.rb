class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Devise authentication
  before_action :authenticate_user!

  # Multi-tenancy: Set current tenant after authentication
  before_action :set_current_tenant

  helper_method :current_project, :current_account

  protected

  # Use auth layout for Devise controllers
  def layout_by_resource
    if devise_controller?
      "auth"
    else
      "application"
    end
  end

  def after_sign_in_path_for(resource)
    dashboard_path
  end

  def current_project
    return @current_project if defined?(@current_project)
    @current_project = current_user.respond_to?(:projects) ? current_user.projects.first : nil
  end

  def current_account
    @current_account ||= current_user&.account
  end

  private

  def set_current_tenant
    if user_signed_in? && current_user.account
      ActsAsTenant.current_tenant = current_user.account
    end
  end

  layout :layout_by_resource
end
