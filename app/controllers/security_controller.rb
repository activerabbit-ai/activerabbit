class SecurityController < ApplicationController
  # Keep views under admin/security
  layout 'admin'
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }

  def index
    @security_events = [
      { type: 'failed_login', ip: '192.168.1.100', count: 5, blocked: true, time: 1.hour.ago },
      { type: 'rate_limit', ip: '10.0.0.50', count: 100, blocked: true, time: 2.hours.ago },
      { type: 'suspicious_activity', ip: '203.0.113.0', count: 1, blocked: false, time: 3.hours.ago }
    ]
  end

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end
end
