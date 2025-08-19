class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Devise authentication
  before_action :authenticate_user!

  protected

  # Use auth layout for Devise controllers
  def layout_by_resource
    if devise_controller?
      "auth"
    else
      "application"
    end
  end

  layout :layout_by_resource
end
