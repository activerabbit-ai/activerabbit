class CheckoutsController < ApplicationController
  before_action :authenticate_user!

  def create
    account = current_user.account
    plan = params.require(:plan)
    interval = params.require(:interval)
    ai = params[:ai]

    url = CheckoutCreator.new(user: current_user, account:, plan:, interval:, ai:).call.url
    redirect_to url, allow_other_host: true, status: :see_other
  rescue => e
    redirect_to settings_path, alert: e.message
  end
end
