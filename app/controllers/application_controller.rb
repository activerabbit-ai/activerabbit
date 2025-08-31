class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # allow_browser versions: :modern  # Temporarily disabled for deployment testing

  # Devise authentication - skip for Devise controllers (sign up, sign in, etc.)
  before_action :authenticate_user!, unless: :devise_controller?

  # Multi-tenancy: Set current tenant after authentication (skip for Devise controllers)
  before_action :set_current_tenant, unless: :devise_controller?

  # Project selection from slug
  before_action :set_current_project_from_slug

  # Onboarding: Redirect users without projects to onboarding
  before_action :check_onboarding_needed

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
    # Safely check onboarding status
    begin
      if resource.needs_onboarding?
        onboarding_welcome_path
      else
        dashboard_path
      end
    rescue ActsAsTenant::Errors::NoTenantSet
      # If tenant isn't set yet, assume onboarding is needed
      onboarding_welcome_path
    end
  end

  def current_project
    @current_project
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

  def set_current_project_from_slug
    return unless user_signed_in?
    return if devise_controller?

    if params[:project_slug].present?
      @current_project = current_account&.projects&.find_by(slug: params[:project_slug])

      # If project not found or doesn't belong to current account, redirect to dashboard
      unless @current_project
        redirect_to dashboard_path, alert: "Project not found or access denied."
        return
      end
    end
  end

  def check_onboarding_needed
    return unless user_signed_in?
    return if devise_controller?
    return if controller_name == 'onboarding'
    return if controller_name == 'projects' # Allow access to projects controller during onboarding

    begin
      if current_user.needs_onboarding?
        redirect_to onboarding_welcome_path
      end
    rescue ActsAsTenant::Errors::NoTenantSet
      # If tenant isn't set, redirect to onboarding
      redirect_to onboarding_welcome_path
    end
  end

  layout :layout_by_resource
end
