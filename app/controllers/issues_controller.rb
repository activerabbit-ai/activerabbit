class IssuesController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project
  before_action :set_issue, only: [:show, :update, :destroy]

  def index
    @issues = @project.issues.includes(:events)

    # Filtering
    @issues = @issues.where(status: params[:status]) if params[:status].present?
    @issues = @issues.where("exception_type ILIKE ?", "%#{params[:exception_type]}%") if params[:exception_type].present?
    @issues = @issues.where("controller_action ILIKE ?", "%#{params[:controller_action]}%") if params[:controller_action].present?

    # Sorting
    case params[:sort]
    when "count"
      @issues = @issues.order(count: :desc)
    when "first_seen"
      @issues = @issues.order(first_seen_at: :desc)
    else
      @issues = @issues.order(last_seen_at: :desc)
    end

    @issues = @issues.page(params[:page]).per(25)

    # Stats
    @stats = {
      total: @project.issues.count,
      open: @project.issues.open.count,
      wip: @project.issues.wip.count,
      closed: @project.issues.closed.count
    }
  end

  def show
    @events = @issue.events.recent.limit(50)
    @related_issues = @project.issues
                              .where(exception_class: @issue.exception_class)
                              .where.not(id: @issue.id)
                              .limit(5)
  end

  def update
    case params[:action_type]
    when "resolve"
      @issue.resolve!
      message = "Issue marked as resolved."
    when "ignore"
      @issue.ignore!
      message = "Issue ignored."
    when "reopen"
      @issue.reopen!
      message = "Issue reopened."
    else
      redirect_to project_issue_path(@project, @issue), alert: "Invalid action."
      return
    end

    redirect_to project_issue_path(@project, @issue), notice: message
  end

  def destroy
    @issue.destroy
    redirect_to project_issues_path(@project), notice: "Issue deleted successfully."
  end

  def bulk_action
    issue_ids = params[:issue_ids] || []
    action = params[:bulk_action]

    if issue_ids.empty?
      redirect_to project_issues_path(@project), alert: "No issues selected."
      return
    end

    issues = @project.issues.where(id: issue_ids)

    case action
    when "resolve"
      issues.each(&:resolve!)
      message = "#{issues.count} issues resolved."
    when "ignore"
      issues.each(&:ignore!)
      message = "#{issues.count} issues ignored."
    when "delete"
      count = issues.count
      issues.destroy_all
      message = "#{count} issues deleted."
    else
      redirect_to project_issues_path(@project), alert: "Invalid bulk action."
      return
    end

    redirect_to project_issues_path(@project), notice: message
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_issue
    @issue = @project.issues.find(params[:id])
  end
end
