class SreInboxController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }

  PENDING_PR_STATUSES = %w[creating_pr pr_created pr_created_review_needed ci_pending ci_passed].freeze

  AGENT_WORKING_PR_STATUSES = %w[creating_pr pr_created ci_pending ci_passed ci_failed].freeze
  NEEDS_REVIEW_PR_STATUSES = %w[pr_created_review_needed].freeze

  def index2
    @project_scope = @current_project || @project

    base = Issue.all
    base = base.where(project_id: @project_scope.id) if @project_scope

    @tabs = {
      "needs_review"   => "Needs review",
      "agent_working"  => "Agent working",
      "shipped"        => "Shipped",
      "all"            => "All errors"
    }
    @active_tab = @tabs.key?(params[:tab]) ? params[:tab] : "needs_review"

    @counts = {
      "needs_review"  => needs_review_scope(base).count,
      "agent_working" => agent_working_scope(base).count,
      "shipped"       => shipped_scope(base).count,
      "all"           => base.count
    }

    @issues = filtered_scope(base, @active_tab)
                .includes(:project)
                .limit(50)
  end

  def index
    @project_scope = @current_project || @project

    base = Issue.all
    base = base.where(project_id: @project_scope.id) if @project_scope

    # ── Stat strip ────────────────────────────────────────────────────
    @ai_resolved_today = base
      .where(resolution_status: "resolved")
      .where("sre_analyzed_at >= ?", Time.current.beginning_of_day)
      .count

    @needs_attention_count = base.where(resolution_status: "needs_attention").count

    @avg_resolution_seconds = compute_avg_resolution_seconds(base)
    @baseline_resolution_seconds = nil # reserved for future "before ActiveRabbit" comparison

    pr_scope = base
      .where.not(auto_fix_pr_number: nil)
      .where(auto_fix_attempted_at: Time.current.beginning_of_month..Time.current)

    @prs_opened_this_month = pr_scope.count
    @prs_merged_this_month = pr_scope.where(auto_fix_status: "merged").count
    @prs_pending_this_month = pr_scope.where(auto_fix_status: PENDING_PR_STATUSES).count

    # ── Row queries ───────────────────────────────────────────────────
    @resolved_issues = base
      .includes(:project)
      .where(resolution_status: "resolved")
      .order(sre_analyzed_at: :desc)
      .limit(20)

    @needs_attention_issues = base
      .includes(:project)
      .where(resolution_status: "needs_attention")
      .severity_ordered
      .limit(20)
  end

  private

  def needs_review_scope(base)
    base.where(
      "resolution_status = ? OR auto_fix_status IN (?)",
      "needs_attention", NEEDS_REVIEW_PR_STATUSES
    )
  end

  def agent_working_scope(base)
    base.where(
      "(resolution_status = ? AND auto_fix_status IS NULL) OR auto_fix_status IN (?)",
      "investigating", AGENT_WORKING_PR_STATUSES
    )
  end

  def shipped_scope(base)
    base.where(
      "auto_fix_status = ? OR (resolution_status = ? AND auto_fix_status IS NULL)",
      "merged", "resolved"
    )
  end

  def filtered_scope(base, tab)
    case tab
    when "needs_review"
      needs_review_scope(base).order(
        Arel.sql("CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 WHEN 'low' THEN 3 ELSE 4 END"),
        last_seen_at: :desc
      )
    when "agent_working"
      agent_working_scope(base).order(last_seen_at: :desc)
    when "shipped"
      shipped_scope(base).order(Arel.sql("COALESCE(auto_fix_merged_at, sre_analyzed_at) DESC NULLS LAST"))
    else
      base.order(last_seen_at: :desc)
    end
  end

  def set_project
    @project = current_account.projects.find(params[:project_id])
  end

  def compute_avg_resolution_seconds(scope)
    resolved = scope.where(resolution_status: "resolved")
                    .where.not(sre_analyzed_at: nil, first_seen_at: nil)
    return 0 if resolved.empty?

    # seconds between first_seen_at and sre_analyzed_at, averaged in SQL
    avg = resolved.pick(Arel.sql("AVG(EXTRACT(EPOCH FROM (sre_analyzed_at - first_seen_at)))"))
    avg.to_f
  end
end
