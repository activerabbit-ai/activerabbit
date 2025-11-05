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
    before_action :set_admin_tenant

    private

    def authorize_admin!
      allowlist = ENV.fetch("ADMIN_EMAIL_ALLOWLIST", "").split(",").map(&:strip).reject(&:blank?)
      return if allowlist.empty? # no restrictions configured
      return if allowlist.include?(current_user&.email)
      redirect_to root_path, alert: "Not authorized"
    end

    def set_admin_tenant
      # Ensure multi-tenant scoping is applied for all admin pages
      if current_user&.account
        ActsAsTenant.current_tenant = current_user.account
      end
    end
  end
end
