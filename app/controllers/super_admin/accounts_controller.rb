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
        accounts = Account.order(created_at: :desc)
        
        if params[:q].present?
          query = params[:q].strip
          
          # Check if searching by project ID (e.g., "project:30" or "p:30")
          if query.match?(/^(project|p):(\d+)$/i)
            project_id = query.match(/^(project|p):(\d+)$/i)[2].to_i
            project = Project.find_by(id: project_id)
            accounts = project ? accounts.where(id: project.account_id) : accounts.none
          
          # Check if searching by user ID (e.g., "user:55" or "u:55")
          elsif query.match?(/^(user|u):(\d+)$/i)
            user_id = query.match(/^(user|u):(\d+)$/i)[2].to_i
            user = User.find_by(id: user_id)
            accounts = user ? accounts.where(id: user.account_id) : accounts.none
          
          # Check if searching by account ID (e.g., "id:30" or just a number)
          elsif query.match?(/^(id:)?(\d+)$/i)
            account_id = query.match(/^(id:)?(\d+)$/i)[2].to_i
            accounts = accounts.where(id: account_id)
          
          # Otherwise search by account name or user email
          else
            search_term = "%#{query.downcase}%"
            accounts = accounts.left_joins(:users)
                               .where("LOWER(accounts.name) LIKE :q OR LOWER(users.email) LIKE :q", q: search_term)
                               .distinct
          end
        end
        
        @pagy, @accounts = pagy(accounts, limit: 25)
        
        # Preload counts without tenant scoping
        account_ids = @accounts.map(&:id)
        @projects_count = Project.where(account_id: account_ids).group(:account_id).count
        @users_count = User.where(account_id: account_ids).group(:account_id).count
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
