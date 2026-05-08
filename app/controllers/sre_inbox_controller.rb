class SreInboxController < ApplicationController
  layout "admin"
  before_action :authenticate_user!

  # ── Tab → auto_fix_status partition ────────────────────────────────
  # Shipped is terminal (merged). Failed PR statuses go to Needs review
  # because they require human input. In-flight statuses go to Agent
  # working. Precedence shipped > needs_review > agent_working — each
  # scope excludes higher-priority bucket ids, so every issue lands in
  # at most one bucket.
  SHIPPED_PR_STATUSES       = %w[merged].freeze
  NEEDS_REVIEW_PR_STATUSES  = %w[pr_created_review_needed ci_failed ci_timeout merge_failed failed monitor_error].freeze
  AGENT_WORKING_PR_STATUSES = %w[creating_pr pr_created ci_pending ci_passed].freeze

  TABS = {
    "needs_review"  => "Needs review",
    "agent_working" => "Agent working",
    "shipped"       => "Shipped",
    "all"           => "All errors"
  }.freeze

  CATEGORIES = %w[error performance job frontend].freeze

  # How many of the most recent issues to auto-analyze the first time
  # anyone opens the inbox for a project.
  AUTO_SEED_COUNT = 20

  def index
    @project_scope = @current_project || selected_project_for_menu
    seed_inbox_if_needed!(@project_scope) if @project_scope

    base = Issue.all
    base = base.where(project_id: @project_scope.id) if @project_scope

    @tabs       = TABS
    @active_tab = TABS.key?(params[:tab]) ? params[:tab] : "needs_review"
    @category   = params[:category].to_s.downcase if CATEGORIES.include?(params[:category].to_s.downcase)

    # Counts always reflect the unfiltered scope so the tab badges don't
    # change when a category filter is applied — only the visible rows do.
    @counts = {
      "needs_review"  => needs_review_scope(base).count,
      "agent_working" => agent_working_scope(base).count,
      "shipped"       => shipped_scope(base).count,
      "all"           => base.count
    }

    scope = ordered_for(filtered_scope(base, @active_tab), @active_tab)
              .includes(:project)
    scope = scope_for_category(scope, @category) if @category

    @issues = scope.limit(50)
  end

  # 301 from legacy /sre_inbox(2) and /:project_slug/sre_inbox(2) URLs.
  # Stashes slug into session/cookie so /inbox lands on the right project.
  def redirect_to_inbox
    if (project = current_account&.projects&.find_by(slug: params[:project_slug]))
      session[:selected_project_slug] = project.slug
      cookies[:last_project_slug] = { value: project.slug, expires: 1.year.from_now }
    end
    qs = request.query_string.presence
    redirect_to(qs ? "/inbox?#{qs}" : "/inbox", status: :moved_permanently)
  end

  private

  # ── Auto-seed: one-time per project, queue analysis for the most
  # recent N un-analyzed issues so the inbox isn't empty on first view.
  # Idempotent — `project.settings["sre_inbox_seeded_at"]` gates re-runs.
  def seed_inbox_if_needed!(project)
    return if ENV["ANTHROPIC_API_KEY"].blank?
    return if project.settings.is_a?(Hash) && project.settings["sre_inbox_seeded_at"].present?

    issue_ids = Issue.where(project_id: project.id, sre_analyzed_at: nil)
                     .order(last_seen_at: :desc)
                     .limit(AUTO_SEED_COUNT)
                     .pluck(:id)
    return if issue_ids.empty?

    # Mark seeded BEFORE queueing so concurrent requests don't double-queue.
    new_settings = (project.settings || {}).merge("sre_inbox_seeded_at" => Time.current.iso8601)
    project.update_columns(settings: new_settings)

    issue_ids.each { |id| AnalyzeIssueJob.perform_async(id) }
    Rails.logger.info("[sre_inbox] auto-seeded project=#{project.slug} count=#{issue_ids.size}")
  end

  # ── Bucket scopes (mutually exclusive via id-subquery exclusion) ───

  def shipped_scope(base)
    base.where(auto_fix_status: SHIPPED_PR_STATUSES).or(
      base.where(resolution_status: "resolved", auto_fix_status: nil)
    )
  end

  def needs_review_scope(base)
    base.where(
          "resolution_status = ? OR auto_fix_status IN (?)",
          "needs_attention", NEEDS_REVIEW_PR_STATUSES
        )
        .where.not(id: shipped_scope(base).select(:id))
  end

  def agent_working_scope(base)
    base.where(
          "(resolution_status = ? AND auto_fix_status IS NULL) OR auto_fix_status IN (?)",
          "investigating", AGENT_WORKING_PR_STATUSES
        )
        .where.not(id: shipped_scope(base).select(:id))
        .where.not(id: needs_review_scope(base).select(:id))
  end

  def filtered_scope(base, tab)
    case tab
    when "needs_review"  then needs_review_scope(base)
    when "agent_working" then agent_working_scope(base)
    when "shipped"       then shipped_scope(base)
    else                      base
    end
  end

  # Mirrors the view's `category_for` lambda. Filters at the SQL layer so
  # the inbox stays performant on large datasets.
  def scope_for_category(scope, category)
    case category
    when "job"
      scope.where(is_job_failure: true)
    when "frontend"
      scope.where(source: "frontend")
    when "performance"
      scope.where(
        "exception_class ~* ? OR (root_cause::jsonb ->> 'triggered_by') = ?",
        "(Timeout|Deadlock|StatementInvalid)",
        "race_condition"
      )
    when "error"
      # "Error" is the catch-all — exclude job/frontend/performance.
      scope.where(is_job_failure: [false, nil])
           .where.not(source: "frontend")
           .where.not(
             "exception_class ~* ? OR (root_cause::jsonb ->> 'triggered_by') = ?",
             "(Timeout|Deadlock|StatementInvalid)",
             "race_condition"
           )
    else
      scope
    end
  end

  def ordered_for(scope, tab)
    case tab
    when "needs_review"
      scope.order(
        Arel.sql("CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 ELSE 4 END"),
        last_seen_at: :desc
      )
    when "shipped"
      scope.order(Arel.sql("COALESCE(auto_fix_merged_at, sre_analyzed_at) DESC NULLS LAST"))
    else # agent_working, all
      scope.order(last_seen_at: :desc)
    end
  end
end
