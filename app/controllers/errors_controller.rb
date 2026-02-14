class ErrorsController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }

  def index
    # Use current_project from ApplicationController (set by slug) or @project (set by project_id)
    project_scope = @current_project || @project

    # Get all issues (errors) ordered by most recent, including resolved ones
    base_scope = project_scope ? project_scope.issues : Issue

    # Always exclude errors from the last minute to avoid showing realtime
    # noise that hasn't been fully processed / grouped yet.
    base_scope = base_scope.where("last_seen_at < ?", 1.minute.ago)

    # Quick filters from summary cards
    case params[:filter]
    when "open"
      base_scope = base_scope.wip
    when "closed"
      base_scope = base_scope.closed
    when "recent"
      base_scope = base_scope.where("last_seen_at > ?", 24.hours.ago)
    when "jobs"
      base_scope = base_scope.from_job_failures
    when "ai"
      base_scope = base_scope.where.not(ai_summary: [nil, ""])
    end

    # Time period filter from header buttons — default to show all
    @current_period = params[:period].presence || "all"
    case @current_period
    when "1h"
      base_scope = base_scope.where("last_seen_at > ?", 1.hour.ago)
    when "1d"
      base_scope = base_scope.where("last_seen_at > ?", 1.day.ago)
    when "7d"
      base_scope = base_scope.where("last_seen_at > ?", 7.days.ago)
    when "30d"
      base_scope = base_scope.where("last_seen_at > ?", 30.days.ago)
    when "all"
      # No time filter — show everything
    end

    @q = base_scope.ransack(params[:q])
    scoped_issues = @q.result.includes(:project).recent

    # Use pagy_countless to skip the expensive SELECT COUNT(*) on millions of rows.
    # Trade-off: we don't show "Page X of Y" or total count in pagination.
    @pagy, @issues = pagy_countless(scoped_issues, limit: 25)

    # ── Summary stats (cached 2 min) ──────────────────────────────────
    # These run on all issues (no period filter) but are cached so they
    # only hit the DB once every 2 minutes per project.
    stats_cache_key = "errors_stats/#{project_scope&.id || 'global'}/#{current_account&.id}"
    stats = Rails.cache.fetch(stats_cache_key, expires_in: 2.minutes) do
      issues_base = project_scope ? project_scope.issues : Issue
      issues_base = issues_base.where("last_seen_at < ?", 1.minute.ago)
      status_counts = issues_base.group(:status).count
      {
        total: status_counts.values.sum,
        wip: status_counts.fetch("wip", 0),
        closed: status_counts.fetch("closed", 0),
        recent: issues_base.where("last_seen_at > ?", 24.hours.ago).count,
        failed_jobs: issues_base.from_job_failures.count,
        ai_summaries: issues_base.where.not(ai_summary: [nil, ""]).count
      }
    end

    @total_errors = stats[:total]
    @open_errors = stats[:wip]
    @resolved_errors = stats[:closed]
    @recent_errors = stats[:recent]
    @failed_jobs_count = stats[:failed_jobs]
    @ai_summaries_count = stats[:ai_summaries]

    # ── Impact metrics (scoped to the 25 issues on this page) ─────────
    issue_ids = @issues.map(&:id)
    if issue_ids.any?
      events_scope = project_scope ? project_scope.events : Event
      cutoff_24h = 24.hours.ago

      # Only count events for the 25 issues on this page (NOT a global count).
      # This uses the composite index (issue_id, occurred_at) — fast even at millions.
      @events_24h_by_issue_id = events_scope
        .where(issue_id: issue_ids)
        .where("occurred_at > ?", cutoff_24h)
        .group(:issue_id)
        .count

      # Approximate total from the page's issues instead of scanning all events
      @total_events_24h = @events_24h_by_issue_id.values.sum

      # Job failure detection — simple WHERE on 25 IDs, no scan needed
      @issue_ids_with_job_failures = Issue.where(id: issue_ids)
        .where("controller_action NOT LIKE '%Controller#%'")
        .pluck(:id)
        .to_set
    else
      @total_events_24h = 0
      @events_24h_by_issue_id = {}
      @issue_ids_with_job_failures = Set.new
    end

    # Optional: build graph data across all errors
    if params[:tab] == "graph"
      range_key = (params[:range] || "7D").to_s.upcase
      window_seconds = case range_key
      when "1H" then 1.hour
      when "4H" then 4.hours
      when "8H" then 8.hours
      when "12H" then 12.hours
      when "24H" then 24.hours
      when "48H" then 48.hours
      when "7D" then 7.days
      when "30D" then 30.days
      else 7.days
      end

      bucket_seconds = case range_key
      when "1H", "4H", "8H" then 5.minutes
      when "12H" then 15.minutes
      when "24H", "48H" then 1.hour
      when "7D", "30D" then 1.day
      else 1.day
      end

      start_time = Time.current - window_seconds
      end_time = Time.current
      bucket_count = ((window_seconds.to_f / bucket_seconds).ceil).clamp(1, 300)

      counts = Array.new(bucket_count, 0)
      labels = Array.new(bucket_count) { |i| start_time + i * bucket_seconds }

      # Use SQL date_trunc + GROUP BY to count events per bucket in the DB.
      # This returns ~7-300 rows instead of loading millions of timestamps into Ruby.
      events_scope = project_scope ? project_scope.events : Event
      trunc_unit = bucket_seconds <= 5.minutes ? "minute" : (bucket_seconds <= 1.hour ? "hour" : "day")
      bucketed = events_scope
        .where(occurred_at: start_time..end_time)
        .group("date_trunc('#{trunc_unit}', occurred_at)")
        .count

      bucketed.each do |truncated_ts, cnt|
        next unless truncated_ts
        idx = ((truncated_ts - start_time) / bucket_seconds).floor.to_i
        next if idx.negative? || idx >= bucket_count
        counts[idx] += cnt
      end

      @graph_labels = labels
      @graph_counts = counts
      @graph_max = [counts.max || 0, 1].max
      @graph_has_data = counts.sum > 0
      @graph_range_key = range_key
    end
  end

  def show
    project_scope = @current_project || @project
    @issue = (project_scope ? project_scope.issues : Issue).find(params[:id])

    # Neighbouring issues for quick navigation
    issue_scope = project_scope ? project_scope.issues : Issue
    @prev_issue = issue_scope.where("id < ?", @issue.id).order(id: :desc).first
    @next_issue = issue_scope.where("id > ?", @issue.id).order(id: :asc).first

    # Calculate impact metrics
    @unique_users_24h = @issue.unique_users_affected_24h
    @events_24h = @issue.events_last_24h
    @primary_environment = @issue.primary_environment
    @current_release = @issue.current_release
    @impact_percentage = @issue.impact_percentage_24h

    # Get most common HTTP method
    @common_method = @issue.events.where.not(request_method: nil)
                           .group(:request_method)
                           .order("count_id DESC")
                           .limit(1)
                           .count(:id)
                           .keys
                           .first

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
    @selected_event =
      if params[:event_id].present?
        @events.find { |e| e.id.to_s == params[:event_id].to_s }
      end
    @selected_event ||= @events.first

    # Graph data for counts over time (only build when requested)
    if params[:tab] == "graph"
      range_key = (params[:range] || "7D").to_s.upcase
      window_seconds = case range_key
      when "1H" then 1.hour
      when "4H" then 4.hours
      when "8H" then 8.hours
      when "12H" then 12.hours
      when "24H" then 24.hours
      when "48H" then 48.hours
      when "7D" then 7.days
      when "30D" then 30.days
      else 24.hours
      end

      bucket_seconds = case range_key
      when "1H", "4H", "8H" then 5.minutes
      when "12H" then 15.minutes
      when "24H", "48H" then 1.hour
      when "7D", "30D" then 1.day
      else 1.hour
      end

      start_time = Time.current - window_seconds
      end_time = Time.current
      bucket_count = ((window_seconds.to_f / bucket_seconds).ceil).clamp(1, 300)

      # Initialize buckets
      counts = Array.new(bucket_count, 0)
      labels = Array.new(bucket_count) { |i| start_time + i * bucket_seconds }

      # Load only events in window (pluck timestamps to reduce AR object overhead)
      event_times = events_scope.where("occurred_at >= ? AND occurred_at <= ?", start_time, end_time).pluck(:occurred_at)
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

    if params[:tab] == "ai"
      Rails.logger.info "[AI Debug] Issue ##{@issue.id} - ai_summary present: #{@issue.ai_summary.present?}, length: #{@issue.ai_summary&.length}"
      if @issue.ai_summary.present?
        @ai_result = { summary: @issue.ai_summary }
        Rails.logger.info "[AI Debug] Set @ai_result with summary length: #{@ai_result[:summary]&.length}"
      elsif @issue.ai_summary_generated_at.present?
        # Already attempted previously and no summary was stored
        @ai_result = { error: "no_summary_available", message: "No AI summary available for this issue." }
      else
        # First-time attempt only
        github_client = github_client_for_issue(@issue)
        result = AiSummaryService.new(issue: @issue, sample_event: @selected_event, github_client: github_client).call
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

  def regenerate_ai_summary
    project_scope = @current_project || @project
    @issue = (project_scope ? project_scope.issues : Issue).find(params[:id])
    @selected_event = @issue.events.order(occurred_at: :desc).first

    # Check quota before generating (ERB handles all quota UI on page reload)
    account = current_user&.account || @issue.account
    if account && !account.within_quota?(:ai_summaries)
      respond_to do |format|
        format.json { render json: { success: false, quota_exceeded: true } }
        format.html do
          flash[:alert] = "AI analysis quota reached."
          redirect_to redirect_path_for_issue(@issue)
        end
      end
      return
    end

    # Force regeneration by clearing the previous summary
    github_client = github_client_for_issue(@issue)
    result = AiSummaryService.new(issue: @issue, sample_event: @selected_event, github_client: github_client).call

    if result[:summary].present?
      @issue.update(ai_summary: result[:summary], ai_summary_generated_at: Time.current)

      respond_to do |format|
        format.json { render json: { success: true } }
        format.html do
          flash[:notice] = "AI summary regenerated successfully."
          redirect_to redirect_path_for_issue(@issue)
        end
      end
    else
      @issue.update(ai_summary: nil, ai_summary_generated_at: Time.current)

      respond_to do |format|
        format.json { render json: { success: false, message: result[:message] || "Failed to generate AI analysis. Please try again." } }
        format.html do
          flash[:alert] = result[:message] || "Failed to generate AI summary."
          redirect_to redirect_path_for_issue(@issue)
        end
      end
    end
  end

  def update
    project_scope = @current_project || @project
    @issue = (project_scope ? project_scope.issues : Issue).find(params[:id])

    if @issue.update(issue_params)
      respond_to do |format|
        format.html do
          redirect_path = if @current_project
                            "/#{@current_project.slug}/errors/#{@issue.id}"
          elsif @project
                            project_error_path(@project, @issue)
          else
                            errors_path
          end
          redirect_to(redirect_path, notice: "Error status updated successfully.")
        end
        format.turbo_stream do
          error_url = if @current_project
                        "/#{@current_project.slug}/errors/#{@issue.id}"
          elsif @project
                        project_error_path(@project, @issue)
          else
                        error_path(@issue)
          end

          # Check if it's from the detail page or list page
          if params[:from_list]
            # Update the list view status dropdown (turbo-frame)
            @issue.reload
            render turbo_stream: [
              turbo_stream.replace(
                "status_dropdown_#{@issue.id}",
                partial: "errors/status_dropdown_list",
                locals: { issue: @issue, project: @project, current_project: @current_project }
              ),
              turbo_stream.append(
                "flash_messages",
                partial: "shared/toast",
                locals: { message: "Status updated successfully", type: "success" }
              )
            ]
          else
            # Update the detail page status dropdown
            render turbo_stream: [
              turbo_stream.replace(
                "status_dropdown",
                partial: "errors/status_dropdown",
                locals: { issue: @issue, error_url: error_url }
              ),
              turbo_stream.append(
                "flash_messages",
                partial: "shared/toast",
                locals: { message: "Status updated successfully", type: "success" }
              )
            ]
          end
        end
      end
    else
      redirect_path = if @current_project
                        "/#{@current_project.slug}/errors/#{@issue.id}"
      elsif @project
                        project_error_path(@project, @issue)
      else
                        errors_path
      end
      redirect_to(redirect_path, alert: "Failed to update error status.")
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
    redirect_to(redirect_path, notice: "Error resolved successfully.")
  end

  def create_pr
    project_scope = @current_project || @project
    @issue = (project_scope ? project_scope.issues : Issue).find(params[:id])

    # Check quota and show warning
    account = current_user&.account
    if account && account.should_warn_before_action?(:pull_requests)
      warning_msg = account.quota_warning_message(:pull_requests)
      flash.now[:warning] = warning_msg if warning_msg
    end

    # Get custom branch name from params (may be empty for AI generation)
    custom_branch_name = params[:branch_name].presence

    pr_service = Github::PrService.new(project_scope || @issue.project)
    result = pr_service.create_pr_for_issue(@issue, custom_branch_name: custom_branch_name)

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
        issue_pr_urls = settings["issue_pr_urls"] || {}
        issue_pr_urls[@issue.id.to_s] = result[:pr_url]
        settings["issue_pr_urls"] = issue_pr_urls
        pr_project.update(settings: settings)
      end

      # Track PR creation for usage monitoring
      account = current_user&.account || pr_project&.account
      if account && current_user
        AiRequest.create!(
          account: account,
          user: current_user,
          request_type: "pull_request",
          occurred_at: Time.current
        )
      end

      # Log whether actual code fix was applied
      if result[:actual_fix_applied]
        Rails.logger.info "[PR Creation] Created PR with actual code fix applied for issue ##{@issue.id}"
      else
        Rails.logger.info "[PR Creation] Created PR with suggestion file only for issue ##{@issue.id}"
      end

      if request.xhr? || request.format.json?
        render json: { success: true, pr_url: result[:pr_url] }
      else
        redirect_to result[:pr_url], allow_other_host: true
      end
    else
      if request.xhr? || request.format.json?
        render json: { success: false, error: result[:error] || "Failed to create PR" }, status: :unprocessable_entity
      else
        redirect_to redirect_path, alert: (result[:error] || "Failed to open PR")
      end
    end
  end

  private

  def redirect_path_for_issue(issue)
    if @current_project
      project_slug_error_path(@current_project.slug, issue, tab: "stack")
    elsif @project
      project_error_path(@project, issue, tab: "stack")
    else
      error_path(issue, tab: "stack")
    end
  end

  def issue_params
    params.require(:issue).permit(:status)
  end

  def set_project
    @project = current_account.projects.find_by(id: params[:project_id])
  
  if @project.nil?

  respond_to do |format|
  # Get GitHub API client for the issue's project (for enhanced AI context)
  format.html { redirect_to errors_path, alert: "Project not found or access denied" }
  def github_client_for_issue(issue)
  format.json { render json: { error: "Project not found" }, status: :not_found }
    project = issue.project
  end
    return nil unless project&.github_repo_full_name.present?
  end

  end
    settings = project.settings || {}
    installation_id = settings["github_installation_id"]
    project_pat = settings["github_pat"]
    env_pat = ENV["GITHUB_TOKEN"]

    token_manager = Github::TokenManager.new(
      project_pat: project_pat,
      installation_id: installation_id,
      env_pat: env_pat,
      project_app_id: settings["github_app_id"],
      project_app_pk: settings["github_app_pk"],
      env_app_id: ENV["AR_GH_APP_ID"],
      env_app_pk: ENV["AR_GH_APP_PK"]
    )

    token = token_manager.get_token
    return nil unless token.present?

    Github::ApiClient.new(token)
  rescue => e
    Rails.logger.warn "[ErrorsController] Could not create GitHub client: #{e.message}"
    nil
  end
end
