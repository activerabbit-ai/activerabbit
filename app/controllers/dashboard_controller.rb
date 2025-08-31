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

  def project_dashboard
    # Project-specific dashboard - @current_project is set by ApplicationController
    unless @current_project
      redirect_to dashboard_path, alert: "Project not found."
      return
    end

    # Project-specific stats (matching the structure expected by the view)
    @stats = {
      total_projects: 1, # We're viewing one specific project
      active_projects: @current_project.active? ? 1 : 0,
      total_issues: @current_project.issues.count,
      open_issues: @current_project.issues.open.count,
      total_events: @current_project.events.count,
      recent_events: @current_project.events.where('occurred_at > ?', 24.hours.ago).count,
      account_users: current_account.users.count,
      active_users: current_account.users.where('current_sign_in_at > ?', 7.days.ago).count
    }

    # Recent activity for this project
    @recent_issues = @current_project.issues.recent.limit(5)
    @recent_events = @current_project.events.recent.limit(10)

    # Set projects to show only the current project in the projects grid
    @projects = [@current_project]

    # Stats for the current project
    @project_stats = {
      @current_project.id => {
        issues_count: @current_project.issues.open.count,
        events_today: @current_project.events.where('created_at > ?', 24.hours.ago).count,
        health_status: @current_project.health_status
      }
    }

    # Use the same dashboard view but with project-specific data
    render :index
  end
end
