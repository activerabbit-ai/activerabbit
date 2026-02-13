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

        # Preload counts and data without tenant scoping
        account_ids = @accounts.map(&:id)
        @projects_count = Project.where(account_id: account_ids).group(:account_id).count
        @users_count = User.where(account_id: account_ids).group(:account_id).count

        # Preload projects grouped by account_id (for showing URLs)
        @projects_by_account = Project.where(account_id: account_ids)
                                       .order(:name)
                                       .group_by(&:account_id)

        # Preload subscription status: { account_id => true/false }
        user_ids_by_account = User.where(account_id: account_ids).pluck(:account_id, :id)
        all_user_ids = user_ids_by_account.map(&:last)
        subscribed_user_ids = Pay::Subscription
                                .joins(:customer)
                                .where(status: %w[active trialing])
                                .where(pay_customers: { owner_type: "User", owner_id: all_user_ids })
                                .joins("INNER JOIN users ON users.id = pay_customers.owner_id")
                                .pluck("users.account_id")
                                .uniq
        @subscribed_accounts = subscribed_user_ids.to_set
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
