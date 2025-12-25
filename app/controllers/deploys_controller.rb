class DeploysController < ApplicationController
  # Keep views under admin/deploys
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }

  def index
    @project_scope = @current_project || @project

    if @project_scope
      @deploys = @project_scope.deploys
                              .includes(:release, :user)
                              .recent
    else
      @deploys = Deploy.includes(:project, :release, :user).recent
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
