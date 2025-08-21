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

      # Group by target (controller action)
      @performance_data = @rollups.group_by(&:target)

      # N+1 queries
      @n_plus_one_incidents = @project.sql_fingerprints
                                     .n_plus_one_candidates
                                     .limit(20)

      # Slow queries
      @slow_queries = @project.sql_fingerprints
                              .slow
                              .limit(20)

      # Calculate project-specific metrics
      recent_rollups = @project.perf_rollups.where('timestamp > ?', 24.hours.ago)
      total_requests = recent_rollups.sum(:request_count)
      total_errors = recent_rollups.sum(:error_count)
      avg_response = recent_rollups.average(:avg_duration_ms)

      @metrics = {
        response_time: avg_response ? "#{avg_response.round(1)}ms" : "N/A",
        throughput: "#{total_requests}/day",
        error_rate: total_requests > 0 ? "#{((total_errors.to_f / total_requests) * 100).round(2)}%" : "0%"
      }
    else
      # Global performance overview
      @projects = current_user.projects.includes(:perf_rollups)

      @global_stats = {}
      total_requests = 0
      total_errors = 0
      response_times = []

      @projects.each do |project|
        recent_rollups = project.perf_rollups.where('timestamp > ?', 24.hours.ago)
        avg_response = recent_rollups.average(:avg_duration_ms)
        requests = recent_rollups.sum(:request_count)
        errors = recent_rollups.sum(:error_count)

        @global_stats[project.id] = {
          avg_response_time: avg_response&.round(2),
          p95_response_time: recent_rollups.average(:p95_duration_ms)&.round(2),
          total_requests: requests,
          error_count: errors
        }

        # Accumulate for global metrics
        total_requests += requests
        total_errors += errors
        response_times << avg_response if avg_response
      end

      # Calculate global metrics
      @metrics = {
        response_time: response_times.any? ? "#{(response_times.sum / response_times.size).round(1)}ms" : "N/A",
        throughput: "#{total_requests}/day",
        error_rate: total_requests > 0 ? "#{((total_errors.to_f / total_requests) * 100).round(2)}%" : "0%"
      }
    end
  end

  def action_detail
    @target = params[:target]

    # Find rollups for this specific target
    @rollups = @project.perf_rollups
                       .where(target: @target)
                       .where('timestamp > ?', 7.days.ago)
                       .order(:timestamp)

    if @rollups.empty?
      redirect_to admin_project_performance_path(@project), alert: "No performance data found for #{@target}"
      return
    end

    # Calculate detailed metrics
    @total_requests = @rollups.sum(:request_count)
    @total_errors = @rollups.sum(:error_count)
    @avg_response_time = @rollups.average(:avg_duration_ms)
    @p50_response_time = @rollups.average(:p50_duration_ms)
    @p95_response_time = @rollups.average(:p95_duration_ms)
    @p99_response_time = @rollups.average(:p99_duration_ms)
    @min_response_time = @rollups.minimum(:min_duration_ms)
    @max_response_time = @rollups.maximum(:max_duration_ms)
    @error_rate = @total_requests > 0 ? ((@total_errors.to_f / @total_requests) * 100).round(2) : 0

    # Group by timeframe for charts
    @hourly_data = @rollups.where('timestamp > ?', 24.hours.ago)
                           .group_by { |r| r.timestamp.beginning_of_hour }

    @daily_data = @rollups.group_by { |r| r.timestamp.beginning_of_day }
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
