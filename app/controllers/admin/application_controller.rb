# All Administrate controllers inherit from this
# `Administrate::ApplicationController`, making it the ideal place to put
# authentication logic or other before_actions.
#
# If you want to add pagination or other controller-level concerns,
# you're free to overwrite the RESTful controller actions.
module Admin
  class ApplicationController < Administrate::ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    private

    def authorize_admin!
      allowlist = ENV.fetch("ADMIN_EMAIL_ALLOWLIST", "").split(",").map(&:strip).reject(&:blank?)
      return if allowlist.empty? && current_user&.admin?
      return if allowlist.include?(current_user&.email)
      redirect_to root_path, alert: "Not authorized"
    end
  end
end
