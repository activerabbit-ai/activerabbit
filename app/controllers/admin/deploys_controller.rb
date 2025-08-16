class Admin::DeploysController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!

  def index
    @deploys = [
      { id: 1, status: 'success', version: 'v1.2.3', deployed_at: 2.hours.ago, duration: '2m 34s' },
      { id: 2, status: 'failed', version: 'v1.2.2', deployed_at: 1.day.ago, duration: '1m 12s' },
      { id: 3, status: 'success', version: 'v1.2.1', deployed_at: 2.days.ago, duration: '3m 45s' }
    ]
  end
end
