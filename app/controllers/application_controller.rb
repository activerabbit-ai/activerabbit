class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # allow_browser versions: :modern  # Temporarily disabled for deployment testing

  # Controllers that should be accessible even without projects (during onboarding)
  ONBOARDING_EXEMPT_CONTROLLERS = %w[
    onboarding
    projects
    pricing
    billing_portal
    checkouts
    subscriptions
    account_settings
    settings
  ].freeze

  # Include Pagy backend for pagination
  include Pagy::Backend

  # Pundit authorization
  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # Devise authentication - skip for Devise controllers (sign up, sign in, etc.)
  before_action :authenticate_user!, unless: :devise_controller?

  # Multi-tenancy: Set current tenant after authentication (skip for Devise controllers)
  before_action :set_current_tenant, unless: :devise_controller?

  # Project selection from slug
  before_action :set_current_project_from_slug

  # Onboarding: Redirect users without projects to onboarding
  before_action :check_onboarding_needed
  # Subscription welcome and banner suppression
  before_action :handle_subscription_welcome
  # Check quota and show flash message
  before_action :check_quota_exceeded
  # Super admin viewing mode: read-only access
  before_action :enforce_read_only_for_super_admin_viewing

  helper_method :current_project, :current_account, :selected_project_for_menu, :viewing_as_super_admin?, :retention_cutoff

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
        new_project_path
      else
        stored_location_for(resource) || dashboard_path
      end
    rescue ActsAsTenant::Errors::NoTenantSet
      # If tenant isn't set yet, check if user has projects without tenant scoping
      has_projects = ActsAsTenant.without_tenant { resource.account&.projects&.exists? }
      if has_projects
        stored_location_for(resource) || dashboard_path
      else
        stored_location_for(resource) || new_project_path
      end
    end
  end

  def current_project
    @current_project
  end

  def current_account
    return @current_account if defined?(@current_account) && @current_account

    # Super admin viewing mode: use viewed account from session
    if current_user&.super_admin? && session[:viewed_account_id].present?
      # Use without_tenant to ensure we can find any account
      @current_account = ActsAsTenant.without_tenant { Account.find_by(id: session[:viewed_account_id]) }
    end

    @current_account ||= current_user&.account
  end

  def viewing_as_super_admin?
    return false unless current_user&.super_admin?
    return false unless session[:viewed_account_id].present?

    # Check if viewing a different account than user's own
    session[:viewed_account_id].to_i != current_user.account_id
  end

  def selected_project_for_menu
    @selected_project_for_menu
  end

  private

  def set_current_tenant
    if user_signed_in? && current_account
      ActsAsTenant.current_tenant = current_account
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

      # Store selected project in session for dashboard menu
      session[:selected_project_slug] = @current_project.slug
    else
      # When on dashboard or other non-project pages, try to use last selected project for menu
      if session[:selected_project_slug].present?
        @selected_project_for_menu = current_account&.projects&.find_by(slug: session[:selected_project_slug])
      end

      # If no selected project in session or project not found, use first project
      @selected_project_for_menu ||= current_account&.projects&.first
    end
  end

  def check_onboarding_needed
    return unless user_signed_in?
    return if devise_controller?
    return if ONBOARDING_EXEMPT_CONTROLLERS.include?(controller_name)
    # Skip onboarding check when super admin is viewing another account
    return if viewing_as_super_admin?

    begin
      if current_user.needs_onboarding?
        redirect_to new_project_path
      end
    rescue ActsAsTenant::Errors::NoTenantSet
      # If tenant isn't set, check if user has projects without tenant scoping
      has_projects = ActsAsTenant.without_tenant { current_user.account&.projects&.exists? }
      redirect_to new_project_path unless has_projects
    end
  end

  def handle_subscription_welcome
    return unless user_signed_in?
    return unless params[:subscribed] == "1"
    plan = params[:plan].presence || current_account&.current_plan
    interval = params[:interval].presence || current_account&.billing_interval
    if plan && !session[:subscription_welcome_shown]
      flash[:notice] = "Welcome! You're on the #{plan.titleize} plan#{interval ? " (#{interval})" : ""}."
      session[:subscription_welcome_shown] = true
      # Hide banner once after subscribe
      session[:suppress_billing_banner] = true
    end
  end

  def check_quota_exceeded
    return unless user_signed_in?
    return if devise_controller?
    return if controller_name == "onboarding"
    return if controller_name == "pricing" # Don't show on pricing page itself
    return unless current_account
    # Skip quota check when super admin is viewing another account
    return if viewing_as_super_admin?

    # Show on every page until plan is upgraded
    message = current_account.quota_exceeded_flash_message
    if message
      flash.now[:alert] = view_context.link_to(message, plan_path, class: "underline hover:text-red-800").html_safe
    end
  end

  # Data retention cutoff for the current account's plan.
  # Free plan: 5 days, paid plans: 31 days.
  # Use this to scope event queries so free plan users only see recent data.
  def retention_cutoff
    @_retention_cutoff ||= current_account&.data_retention_cutoff
  end

  def user_not_authorized
    redirect_to root_path, alert: "You don't have permission to perform this action"
  end

  # Controllers that super admins can write to while viewing another account
  SUPER_ADMIN_WRITABLE_CONTROLLERS = %w[
    settings
    account_settings
    project_settings
  ].freeze

  # Super admin viewing mode: block most write operations (allow settings changes)
  def enforce_read_only_for_super_admin_viewing
    return unless viewing_as_super_admin?
    return if request.get? || request.head?

    # Allow super admin to exit viewing mode
    return if controller_path == "super_admin/accounts" && action_name == "exit"

    # Allow super admin to change settings on the viewed account
    return if SUPER_ADMIN_WRITABLE_CONTROLLERS.include?(controller_name)

    redirect_back fallback_location: dashboard_path, alert: "View-only mode: You cannot make changes while viewing another account."
  end

  layout :layout_by_resource
end
