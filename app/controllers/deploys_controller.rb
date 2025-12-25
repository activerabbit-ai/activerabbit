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
                              .to_a

      @max_live_seconds = @deploys.each_with_index.map do |deploy, i|
        next_deploy = i.positive? ? @deploys[i - 1] : nil
        deploy.live_for_seconds(next_deploy)
      end.max.to_f

      @max_errors = @deploys.map(&:errors_count).max.to_f

      @max_errors_per_hour = @deploys.each_with_index.map do |deploy, i|
        next_deploy = i.positive? ? @deploys[i - 1] : nil
        deploy.errors_per_hour(next_deploy)
      end.max.to_f
    else
      @deploys = Deploy.includes(:project, :release, :user).recent
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
