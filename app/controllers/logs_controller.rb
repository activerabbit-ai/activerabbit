class LogsController < ApplicationController
  # Keep views under admin/logs
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }

  def index
    # Account-scoped logs (mock data for now, replace with real log aggregation)
    account_name = current_account&.name || "Unknown Account"
    project_names = current_account&.projects&.pluck(:name) || []

    @logs = [
      { level: "info", message: "User signed in to #{account_name}", timestamp: 5.minutes.ago, project: project_names.first },
      { level: "info", message: "New error reported in #{project_names.first || 'project'}", timestamp: 10.minutes.ago, project: project_names.first },
      { level: "warn", message: "High error rate detected in #{account_name}", timestamp: 15.minutes.ago, project: project_names.first },
      { level: "info", message: "Performance alert resolved for #{account_name}", timestamp: 20.minutes.ago, project: project_names.first }
    ].compact
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end
end
