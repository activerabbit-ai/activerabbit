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
    @events = @issue.events.recent.limit(20)
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

  private

  def issue_params
    params.require(:issue).permit(:status)
  end

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end
end
