class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Devise authentication
  before_action :authenticate_user!

  helper_method :current_project

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

  layout :layout_by_resource
end
