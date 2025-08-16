class Admin::LogsController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!

  def index
    @logs = [
      { level: 'info', message: 'User authentication successful', timestamp: 5.minutes.ago },
      { level: 'warn', message: 'High memory usage detected', timestamp: 10.minutes.ago },
      { level: 'error', message: 'Database query timeout', timestamp: 15.minutes.ago },
      { level: 'info', message: 'Background job completed', timestamp: 20.minutes.ago }
    ]
  end
end
