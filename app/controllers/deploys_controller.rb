class DeploysController < ApplicationController
  # Keep views under admin/deploys
  layout 'admin'
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }

  def index
    @deploys = [
      { id: 1, status: 'success', version: 'v1.2.3', deployed_at: 2.hours.ago, duration: '2m 34s' },
      { id: 2, status: 'failed', version: 'v1.2.2', deployed_at: 1.day.ago, duration: '1m 12s' },
      { id: 3, status: 'success', version: 'v1.2.1', deployed_at: 2.days.ago, duration: '3m 45s' }
    ]
  end

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end
end
