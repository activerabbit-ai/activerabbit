class BillingPortalController < ApplicationController
  before_action :authenticate_user!

  def create
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"] if defined?(Stripe) && (Stripe.api_key.nil? || Stripe.api_key.to_s.strip.empty?)
    user = current_user
    user.set_payment_processor :stripe if user.payment_processor.blank?
    if user.payment_processor.processor_id.blank?
      stripe_customer = Stripe::Customer.create(
        email: user.email,
        metadata: { user_id: user.id, account_id: user.account_id }
      )
      user.payment_processor.update!(processor_id: stripe_customer.id)
    end
    session = Stripe::BillingPortal::Session.create(
      customer: user.payment_processor.processor_id,
      return_url: dashboard_url
    )
    redirect_to session.url, allow_other_host: true
  end
end
