class SubscriptionsController < ApplicationController
  before_action :authenticate_user!

  def new
    # Example subscription setup for Pay gem
    @plans = [
      {
        name: "Basic Plan",
        price: "$9.99/month",
        features: ["Feature 1", "Feature 2", "Feature 3"],
        stripe_price_id: "price_basic_monthly" # Replace with your actual Stripe price ID
      },
      {
        name: "Pro Plan",
        price: "$19.99/month",
        features: ["All Basic features", "Feature 4", "Feature 5", "Priority support"],
        stripe_price_id: "price_pro_monthly" # Replace with your actual Stripe price ID
      }
    ]
  end

  def create
    # Create a subscription using Pay gem
    @subscription = current_user.payment_processor.subscribe(
      name: params[:plan_name],
      plan: params[:stripe_price_id]
    )

    if @subscription.active?
      redirect_to root_path, notice: "Successfully subscribed to #{params[:plan_name]}!"
    else
      redirect_to new_subscription_path, alert: "There was an error processing your subscription."
    end
  rescue Pay::Error => e
    redirect_to new_subscription_path, alert: "Payment error: #{e.message}"
  end

  def show
    @subscriptions = current_user.payment_processor.subscriptions
  end

  def destroy
    @subscription = current_user.payment_processor.subscriptions.find(params[:id])
    @subscription.cancel
    redirect_to subscriptions_path, notice: "Subscription cancelled successfully."
  end
end
