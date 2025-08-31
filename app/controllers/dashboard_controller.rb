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

    # Recent activity (account-scoped) - keeping recent_events for potential future use
    @recent_events = Event.recent.limit(10)
    @recent_projects = account_projects.order(created_at: :desc).limit(3)

    # Projects data for the projects grid (same as projects index)
    @projects = current_account.projects.includes(:api_tokens, :issues, :events, :user)
                               .order(:name)

    # Stats for each project
    @project_stats = {}
    @projects.each do |project|
      @project_stats[project.id] = {
        issues_count: project.issues.open.count,
        events_today: project.events.where('created_at > ?', 24.hours.ago).count,
        health_status: project.health_status
      }
    end
  end
end
