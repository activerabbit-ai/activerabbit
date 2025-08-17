class Admin::PerformanceController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }

  def index
    if @project
      # Single project performance view
      @timeframe = params[:timeframe] || 'hour'
      @hours_back = (params[:hours_back] || 24).to_i

      @rollups = @project.perf_rollups
                         .where(timeframe: @timeframe)
                         .where('timestamp > ?', @hours_back.hours.ago)
                         .order(:timestamp)

      # Group by controller action
      @performance_data = @rollups.group_by(&:controller_action)

      # N+1 queries
      @n_plus_one_incidents = @project.sql_fingerprints
                                     .n_plus_one_candidates
                                     .limit(20)

      # Slow queries
      @slow_queries = @project.sql_fingerprints
                              .slow
                              .limit(20)
    else
      # Global performance overview
      @projects = current_user.projects.includes(:perf_rollups)

      @global_stats = {}
      @projects.each do |project|
        recent_rollups = project.perf_rollups.where('timestamp > ?', 24.hours.ago)
        @global_stats[project.id] = {
          avg_response_time: recent_rollups.average(:avg_duration_ms)&.round(2),
          p95_response_time: recent_rollups.average(:p95_duration_ms)&.round(2),
          total_requests: recent_rollups.sum(:request_count),
          error_count: recent_rollups.sum(:error_count)
        }
      end
    end
  end

  def sql_fingerprints
    @sql_fingerprints = @project.sql_fingerprints.includes(:project)

    # Filtering
    case params[:filter]
    when 'slow'
      @sql_fingerprints = @sql_fingerprints.slow
    when 'frequent'
      @sql_fingerprints = @sql_fingerprints.frequent
    when 'n_plus_one'
      @sql_fingerprints = @sql_fingerprints.n_plus_one_candidates
    end

    @sql_fingerprints = @sql_fingerprints.page(params[:page]).per(25)
  end

  def sql_fingerprint
    @sql_fingerprint = @project.sql_fingerprints.find(params[:id])
    @recent_events = @project.events
                             .where("payload->>'sql_queries' IS NOT NULL")
                             .where('created_at > ?', 7.days.ago)
                             .limit(50)
  end

  def create_n_plus_one_pr
    @sql_fingerprint = @project.sql_fingerprints.find(params[:id])

    # This is a stub for GitHub integration
    # In a real implementation, this would create a PR with optimization suggestions

    pr_service = GithubPrService.new(@project)
    result = pr_service.create_n_plus_one_fix_pr(@sql_fingerprint)

    if result[:success]
      redirect_to admin_project_performance_sql_fingerprint_path(@project, @sql_fingerprint),
                  notice: "PR created: #{result[:pr_url]}"
    else
      redirect_to admin_project_performance_sql_fingerprint_path(@project, @sql_fingerprint),
                  alert: "Failed to create PR: #{result[:error]}"
    end
  end

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end
end
