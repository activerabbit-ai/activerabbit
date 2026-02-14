class DashboardController < ApplicationController
  layout "admin"
  before_action :authenticate_user!

  def index
    # Projects data for the projects grid (avoid preloading heavy associations)
    @projects = current_account.projects.includes(:api_tokens, :user)
                               .order(:name)

    project_ids = @projects.map(&:id)

    # ── Cached dashboard stats (2-min TTL) ──────────────────────────────
    # The dashboard was running 14+ live COUNT queries on every page load
    # with no caching, causing timeouts for accounts with large event tables.
    stats_cache_key = "dashboard_stats/#{current_account.id}"
    @stats = Rails.cache.fetch(stats_cache_key, expires_in: 2.minutes) do
      account_projects = current_account.projects
      account_users    = current_account.users

      # Use cached column instead of live COUNT(*) on potentially millions of rows
      total_events = current_account.cached_events_used || 0

      # Use daily_event_counts roll-up table, scoped to the plan's retention period
      retention_window = (current_account.data_retention_days || 31).days.ago.to_date
      events_last_30 = DailyEventCount
                         .where(account_id: current_account.id)
                         .where("day >= ?", retention_window)
                         .sum(:count)

      {
        total_projects: account_projects.count,
        active_projects: account_projects.where(active: true).count,
        total_issues: Issue.count,
        open_issues: Issue.open.count,
        total_events: total_events,
        events_today: Event.where("occurred_at > ?", 24.hours.ago).count,
        events_last_30_days: events_last_30,
        ai_summaries: Issue.where.not(ai_summary: [nil, ""]).count,
        account_users: account_users.count,
        active_users: account_users.where("current_sign_in_at > ?", 7.days.ago).count
      }
    end

    # Sidekiq queue stats for the dashboard health widget
    @sidekiq_stats = begin
      stats = Sidekiq::Stats.new
      queues = Sidekiq::Queue.all.map { |q| { name: q.name, size: q.size, latency: q.latency.round(1) } }
      queues.sort_by! { |q| -q[:size] }
      {
        enqueued: stats.enqueued,
        processed: stats.processed,
        failed: stats.failed,
        busy: Sidekiq::WorkSet.new.size,
        retry_size: stats.retry_size,
        dead_size: stats.dead_size,
        scheduled_size: stats.scheduled_size,
        processes: stats.processes_size,
        queues: queues
      }
    rescue => e
      Rails.logger.warn "[Dashboard] Sidekiq stats unavailable: #{e.message}"
      nil
    end

    # Recent activity (account-scoped, respects data retention)
    recent_cutoff = [24.hours.ago, retention_cutoff].compact.max
    @recent_events = Event.where("occurred_at > ?", recent_cutoff).order(occurred_at: :desc).limit(10)
    @recent_projects = current_account.projects.order(created_at: :desc).limit(3)

    # ── Cached per-project stats (2-min TTL) ────────────────────────────
    project_stats_cache_key = "dashboard_project_stats/#{current_account.id}"
    cached_project_stats = Rails.cache.fetch(project_stats_cache_key, expires_in: 2.minutes) do
      issues_counts_by_project   = Issue.open.where(project_id: project_ids).group(:project_id).count
      events_today_by_project    = Event.where(project_id: project_ids)
                                        .where("occurred_at > ?", 24.hours.ago)
                                        .group(:project_id).count
      ai_summaries_by_project    = Issue.where(project_id: project_ids)
                                        .where.not(ai_summary: [nil, ""])
                                        .group(:project_id).count

      # Use issue count as a proxy instead of scanning the entire events table per project.
      # Total events per project was the single most expensive query on the dashboard.
      issues_total_by_project    = Issue.where(project_id: project_ids).group(:project_id).sum(:count)

      { issues: issues_counts_by_project,
        events_today: events_today_by_project,
        issues_total: issues_total_by_project,
        ai_summaries: ai_summaries_by_project }
    end

    @project_stats = {}
    @projects.each do |project|
      issue_pr_urls = project.settings&.dig("issue_pr_urls") || {}
      perf_pr_urls  = project.settings&.dig("perf_pr_urls") || {}

      @project_stats[project.id] = {
        issues_count: cached_project_stats[:issues][project.id].to_i,
        events_today: cached_project_stats[:events_today][project.id].to_i,
        events_total: cached_project_stats[:issues_total][project.id].to_i,
        ai_summaries: cached_project_stats[:ai_summaries][project.id].to_i,
        health_status: project.health_status,
        issue_pr_urls: issue_pr_urls,
        perf_pr_urls: perf_pr_urls
      }
    end
  end

  def project_dashboard
    # Redirect slug-based project URLs to the full project details page
    unless @current_project
      redirect_to dashboard_path, alert: "Project not found."
      return
    end

    # Redirect to Errors by default when switching/landing on a project
    redirect_to project_slug_errors_path(@current_project.slug)
  end
end
