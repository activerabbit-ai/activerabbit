module SuperAdmin
  class AccountsController < ApplicationController
    layout "admin"
    
    before_action :require_super_admin
    before_action :set_account, only: [:show, :switch]

    # Skip callbacks that might interfere with super admin pages
    skip_before_action :check_onboarding_needed
    skip_before_action :set_current_project_from_slug
    skip_before_action :check_quota_exceeded

    def index
      # Use without_tenant to query all accounts across the system
      ActsAsTenant.without_tenant do
        accounts = Account.includes(:users, :projects).order(created_at: :desc)
        @pagy, @accounts = pagy(accounts, limit: 25)
      end
    end

    def show
      # Use without_tenant to access the specific account's data
      ActsAsTenant.without_tenant do
        @projects = @account.projects.order(created_at: :desc)
        @users = @account.users.order(created_at: :desc)
      end
    end

    def switch
      session[:viewed_account_id] = @account.id
      redirect_to dashboard_path, notice: "Now viewing as #{@account.name}"
    end

    def exit
      session.delete(:viewed_account_id)
      redirect_to super_admin_accounts_path, notice: "Returned to your account"
    end

    private

    def require_super_admin
      unless current_user&.super_admin?
        redirect_to root_path, alert: "Access denied"
      end
    end

    def set_account
      # Use without_tenant to find any account in the system
      ActsAsTenant.without_tenant do
        @account = Account.find(params[:id])
      end
    end
  end
end
