class Admin::ErrorsController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!

  def index
    @errors = [
      { id: 1, message: 'Database connection timeout', count: 23, last_seen: 1.hour.ago, severity: 'high' },
      { id: 2, message: 'API rate limit exceeded', count: 45, last_seen: 30.minutes.ago, severity: 'medium' },
      { id: 3, message: 'Invalid user session', count: 12, last_seen: 2.hours.ago, severity: 'low' }
    ]
  end
end
