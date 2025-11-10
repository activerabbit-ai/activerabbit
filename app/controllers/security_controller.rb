class SecurityController < ApplicationController
  # Keep views under admin/security
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }

  def index
    # Account-scoped security events (mock data for now)
    account_name = current_account&.name || "Unknown Account"

    @security_events = [
      { type: "api_access", account: account_name, ip: "192.168.1.100", count: 25, blocked: false, time: 1.hour.ago },
      { type: "error_ingestion", account: account_name, ip: "10.0.0.50", count: 150, blocked: false, time: 2.hours.ago },
      { type: "performance_data", account: account_name, ip: "203.0.113.0", count: 75, blocked: false, time: 3.hours.ago }
    ]

    @account_stats = {
      api_calls_today: 1250,
      unique_ips: 3,
      blocked_requests: 0,
      account_name: account_name
    }
  end

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end
end
