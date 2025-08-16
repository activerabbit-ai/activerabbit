class Admin::PerformanceController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!

  def index
    @metrics = {
      response_time: '245ms',
      throughput: '1,234 req/min',
      error_rate: '0.12%',
      cpu_usage: '45%',
      memory_usage: '62%'
    }
  end
end
