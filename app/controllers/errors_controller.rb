class ErrorsController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }

  def index
    # Use current_project from ApplicationController (set by slug) or @project (set by project_id)
    project_scope = @current_project || @project

    # Get all issues (errors) ordered by most recent, including resolved ones
    scope = project_scope ? project_scope.issues : Issue
    @issues = scope.includes(:project)
                   .recent
                   .limit(50)

    # Get summary stats scoped to current project or global
    if project_scope
      @total_errors = project_scope.issues.count
      @open_errors = project_scope.issues.open.count
      @resolved_errors = project_scope.issues.closed.count
      @recent_errors = project_scope.issues.where('last_seen_at > ?', 1.hour.ago).count
    else
      @total_errors = Issue.count
      @open_errors = Issue.open.count
      @resolved_errors = Issue.closed.count
      @recent_errors = Issue.where('last_seen_at > ?', 1.hour.ago).count
    end
  end

  def show
    project_scope = @current_project || @project
    @issue = (project_scope ? project_scope.issues : Issue).find(params[:id])
    events_scope = @issue.events

    # Simple filters for Samples table
    events_scope = events_scope.where(server_name: params[:server_name]) if params[:server_name].present?
    events_scope = events_scope.where(request_method: params[:request_method]) if params[:request_method].present?
    events_scope = events_scope.where(request_path: params[:request_path]) if params[:request_path].present?
    events_scope = events_scope.where(request_id: params[:request_id]) if params[:request_id].present?
    events_scope = events_scope.where(release_version: params[:release_version]) if params[:release_version].present?

    # Load recent events after applying DB-level filters
    @events = events_scope.recent.limit(20)

    # Optional filter on error_status inside JSON context (fallback to in-memory if DB JSON querying is not enabled)
    if params[:error_status].present?
      @events = @events.select { |e| e.context.is_a?(Hash) && e.context["error_status"].to_s == params[:error_status].to_s }
    end

    # Selected sample for detailed tags section
    @selected_event = if params[:event_id].present?
                        @events.find { |e| e.id.to_s == params[:event_id].to_s }
                      end
    @selected_event ||= @events.first

    # Graph data for counts over time (only build when requested)
    if params[:tab] == 'graph'
      range_key = (params[:range] || '24H').to_s.upcase
      window_seconds = case range_key
                       when '1H' then 1.hour
                       when '4H' then 4.hours
                       when '8H' then 8.hours
                       when '12H' then 12.hours
                       when '24H' then 24.hours
                       when '48H' then 48.hours
                       when '7D' then 7.days
                       when '30D' then 30.days
                       else 24.hours
                       end

      bucket_seconds = case range_key
                       when '1H', '4H', '8H' then 5.minutes
                       when '12H' then 15.minutes
                       when '24H', '48H' then 1.hour
                       when '7D', '30D' then 1.day
                       else 1.hour
                       end

      start_time = Time.current - window_seconds
      end_time = Time.current
      bucket_count = ((window_seconds.to_f / bucket_seconds).ceil).clamp(1, 300)

      # Initialize buckets
      counts = Array.new(bucket_count, 0)
      labels = Array.new(bucket_count) { |i| start_time + i * bucket_seconds }

      # Load only events in window (pluck timestamps to reduce AR object overhead)
      event_times = events_scope.where('occurred_at >= ? AND occurred_at <= ?', start_time, end_time).pluck(:occurred_at)
      event_times.each do |ts|
        idx = (((ts - start_time) / bucket_seconds).floor).to_i
        next if idx.negative? || idx >= bucket_count
        counts[idx] += 1
      end

      @graph_labels = labels
      @graph_counts = counts
      @graph_max = [counts.max || 0, 1].max
      @graph_has_data = counts.sum > 0
      @graph_range_key = range_key
    end

    if params[:tab] == 'ai'
      if @issue.ai_summary.present?
        @ai_result = { summary: @issue.ai_summary }
      elsif @issue.ai_summary_generated_at.present?
        # Already attempted previously and no summary was stored
        @ai_result = { error: 'no_summary_available', message: 'No AI summary available for this issue.' }
      else
        # First-time attempt only
        result = AiSummaryService.new(issue: @issue, sample_event: @selected_event).call
        if result[:summary].present?
          @issue.update(ai_summary: result[:summary], ai_summary_generated_at: Time.current)
        else
          # Mark attempt even if empty to avoid repeated calls
          @issue.update(ai_summary_generated_at: Time.current)
        end
        @ai_result = result
      end
    end
  end

  def update
    project_scope = @current_project || @project
    @issue = (project_scope ? project_scope.issues : Issue).find(params[:id])

    if @issue.update(issue_params)
      redirect_path = if @current_project
                        "/#{@current_project.slug}/errors/#{@issue.id}"
                      elsif @project
                        project_error_path(@project, @issue)
                      else
                        errors_path
                      end
      redirect_to(redirect_path, notice: 'Error status updated successfully.')
    else
      redirect_path = if @current_project
                        "/#{@current_project.slug}/errors/#{@issue.id}"
                      elsif @project
                        project_error_path(@project, @issue)
                      else
                        errors_path
                      end
      redirect_to(redirect_path, alert: 'Failed to update error status.')
    end
  end

  def destroy
    project_scope = @current_project || @project
    @issue = (project_scope ? project_scope.issues : Issue).find(params[:id])
    @issue.close!  # Mark as closed/resolved instead of deleting

    redirect_path = if @current_project
                      "/#{@current_project.slug}/errors"
                    elsif @project
                      project_errors_path(@project)
                    else
                      errors_path
                    end
    redirect_to(redirect_path, notice: 'Error resolved successfully.')
  end

  def create_pr
    project_scope = @current_project || @project
    @issue = (project_scope ? project_scope.issues : Issue).find(params[:id])

    pr_service = GithubPrService.new(project_scope || @issue.project)
    result = pr_service.create_pr_for_issue(@issue)

    redirect_path = if @current_project
                      "/#{@current_project.slug}/errors/#{@issue.id}"
                    elsif @project
                      project_error_path(@project, @issue)
                    else
                      error_path(@issue)
                    end

    if result[:success]
      # Persist PR URL for this issue so the UI can show a direct link next time
      pr_project = project_scope || @issue.project
      if pr_project
        settings = pr_project.settings || {}
        issue_pr_urls = settings['issue_pr_urls'] || {}
        issue_pr_urls[@issue.id.to_s] = result[:pr_url]
        settings['issue_pr_urls'] = issue_pr_urls
        pr_project.update(settings: settings)
      end

      # Open PR in the new tab by redirecting directly to GitHub
      redirect_to result[:pr_url], allow_other_host: true
    else
      redirect_to redirect_path, alert: (result[:error] || 'Failed to open PR')
    end
  end

  private

  def issue_params
    params.require(:issue).permit(:status)
  end

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end
end
