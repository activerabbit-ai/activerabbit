class DeploysController < ApplicationController
  # Keep views under admin/deploys
  layout 'admin'
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }

  def index
    # Use current_project from ApplicationController (set by slug) or @project (set by project_id)
    project_scope = @current_project || @project

    if project_scope
      # Project-specific deploys (mock data for now)
      @deploys = [
        { id: 1, status: 'success', version: 'v1.2.3', deployed_at: 2.hours.ago, duration: '2m 34s', project: project_scope.name },
        { id: 2, status: 'failed', version: 'v1.2.2', deployed_at: 1.day.ago, duration: '1m 12s', project: project_scope.name },
        { id: 3, status: 'success', version: 'v1.2.1', deployed_at: 2.days.ago, duration: '3m 45s', project: project_scope.name }
      ]
      @project_name = project_scope.name
    else
      # Global deploys across all projects
      @deploys = [
        { id: 1, status: 'success', version: 'v1.2.3', deployed_at: 2.hours.ago, duration: '2m 34s', project: 'Project A' },
        { id: 2, status: 'failed', version: 'v1.2.2', deployed_at: 1.day.ago, duration: '1m 12s', project: 'Project B' },
        { id: 3, status: 'success', version: 'v1.2.1', deployed_at: 2.days.ago, duration: '3m 45s', project: 'Project A' }
      ]
    end
  end

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end
end
