class CheckoutsController < ApplicationController
  before_action :authenticate_user!

  def create
    account = current_user.account
    plan = params.require(:plan)
    interval = params[:interval] # Optional for free plan
    ai = params[:ai]

    # Handle free plan separately (no Stripe checkout needed)
    if plan == "free"
      account.update!(
        current_plan: "free",
        billing_interval: "month" # Default, doesn't matter for free
      )
      redirect_to dashboard_path, notice: "You're now on the Free plan!"
      return
    end

    # For paid plans, go through Stripe checkout
    url = CheckoutCreator.new(user: current_user, account:, plan:, interval:, ai:).call.url
    redirect_to url, allow_other_host: true, status: :see_other
  rescue => e
    redirect_to settings_path, alert: e.message
  end
end
