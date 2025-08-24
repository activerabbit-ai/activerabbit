class PublicController < ApplicationController
  # Skip authentication for public demo
  skip_before_action :authenticate_user!
  layout 'admin'

  def errors
    # Get all issues (errors) ordered by most recent
    @issues = Issue.includes(:project)
                   .recent
                   .limit(50)

    # Get some summary stats
    @total_errors = Issue.count
    @open_errors = Issue.open.count
    @recent_errors = Issue.where('last_seen_at > ?', 1.hour.ago).count

    render 'admin/errors/index'
  end
end
