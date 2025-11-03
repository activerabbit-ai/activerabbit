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
      events_today: Event.where('occurred_at > ?', 24.hours.ago).count,
      events_last_30_days: Event.where('occurred_at > ?', 30.days.ago).count,
      account_users: account_users.count,
      active_users: account_users.where('current_sign_in_at > ?', 7.days.ago).count
    }

    # Recent activity (account-scoped) - keeping recent_events for potential future use
    @recent_events = Event.recent.limit(10)
    @recent_projects = account_projects.order(created_at: :desc).limit(3)

    # Projects data for the projects grid (avoid preloading heavy associations)
    @projects = current_account.projects.includes(:api_tokens, :user)
                               .order(:name)

    # Precompute stats per project to avoid N+1 COUNT queries
    project_ids = @projects.map(&:id)
    issues_counts_by_project = Issue.open.where(project_id: project_ids).group(:project_id).count
    events_today_by_project = Event.where(project_id: project_ids)
                                   .where('occurred_at > ?', 24.hours.ago)
                                   .group(:project_id).count

    # Stats for each project
    @project_stats = {}
    @projects.each do |project|
      issue_pr_urls = project.settings&.dig('issue_pr_urls') || {}
      perf_pr_urls = project.settings&.dig('perf_pr_urls') || {}

      @project_stats[project.id] = {
        issues_count: issues_counts_by_project[project.id].to_i,
        events_today: events_today_by_project[project.id].to_i,
        health_status: project.health_status,
        issue_pr_urls: issue_pr_urls,
        perf_pr_urls: perf_pr_urls
      }
    end
  end

  def project_dashboard
    # Redirect slug-based project URLs to the full project details page
    unless @current_project
      redirect_to dashboard_path, alert: 'Project not found.'
      return
    end

    # Redirect to the full project show page
    redirect_to project_path(@current_project)
  end
end
