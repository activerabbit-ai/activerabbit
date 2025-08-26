class ErrorsController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }

  def index
    # Get all issues (errors) ordered by most recent, including resolved ones
    scope = @project ? @project.issues : Issue
    @issues = scope.includes(:project)
                   .recent
                   .limit(50)

    # Get some summary stats
    @total_errors = Issue.count
    @open_errors = Issue.open.count
    @resolved_errors = Issue.closed.count
    @recent_errors = Issue.where('last_seen_at > ?', 1.hour.ago).count
  end

  def show
    @issue = (@project ? @project.issues : Issue).find(params[:id])
    @events = @issue.events.recent.limit(20)
  end

  def update
    @issue = (@project ? @project.issues : Issue).find(params[:id])

    if @issue.update(issue_params)
      redirect_to(@project ? project_error_path(@project, @issue) : errors_path, notice: 'Error status updated successfully.')
    else
      redirect_to(@project ? project_error_path(@project, @issue) : errors_path, alert: 'Failed to update error status.')
    end
  end

  def destroy
    @issue = (@project ? @project.issues : Issue).find(params[:id])
    @issue.close!  # Mark as closed/resolved instead of deleting
    redirect_to(@project ? project_errors_path(@project) : errors_path, notice: 'Error resolved successfully.')
  end

  private

  def issue_params
    params.require(:issue).permit(:status)
  end

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end
end
