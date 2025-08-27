class DashboardController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!

  def index
    # Account-scoped dashboard metrics
    account_projects = current_account.projects
    account_users = current_account.users

    @stats = {
      total_projects: account_projects.count,
      active_projects: account_projects.where(active: true).count,
      total_issues: Issue.count, # Automatically scoped by acts_as_tenant
      open_issues: Issue.open.count,
      total_events: Event.count, # Automatically scoped by acts_as_tenant
      recent_events: Event.where('occurred_at > ?', 24.hours.ago).count,
      account_users: account_users.count,
      active_users: account_users.where('current_sign_in_at > ?', 7.days.ago).count
    }

    # Recent activity (account-scoped)
    @recent_issues = Issue.recent.limit(5)
    @recent_events = Event.recent.limit(10)
    @recent_projects = account_projects.order(created_at: :desc).limit(3)

    # Health status for account projects
    @system_health = {
      total_healthchecks: Healthcheck.count,
      healthy_checks: Healthcheck.where(status: 'healthy').count,
      warning_checks: Healthcheck.where(status: 'warning').count,
      critical_checks: Healthcheck.where(status: 'critical').count
    }
  end
end
