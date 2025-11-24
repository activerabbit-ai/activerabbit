class BillingPortalController < ApplicationController
  before_action :authenticate_user!

  def create
    Stripe.api_key = ENV["STRIPE_SECRET_KEY"] if defined?(Stripe) && (Stripe.api_key.nil? || Stripe.api_key.to_s.strip.empty?)
    user = current_user
    user.set_payment_processor :stripe if user.payment_processor.blank?

    begin
      ensure_stripe_customer!(user)
      session = Stripe::BillingPortal::Session.create(
        customer: user.payment_processor.processor_id,
        return_url: dashboard_url
      )
      redirect_to session.url, allow_other_host: true
    rescue Stripe::InvalidRequestError => e
      # Handle stale / deleted Stripe customers gracefully
      if e.message&.include?("No such customer")
        Rails.logger.warn "Stripe customer missing for user #{user.id}, recreating: #{e.message}"
        recreate_stripe_customer!(user)
        session = Stripe::BillingPortal::Session.create(
          customer: user.payment_processor.processor_id,
          return_url: dashboard_url
        )
        redirect_to session.url, allow_other_host: true
      else
        Rails.logger.error "Stripe billing portal error for user #{user.id}: #{e.message}"
        redirect_to settings_path, alert: "Unable to open billing portal: #{e.message}"
      end
    end
  end

  private

  def ensure_stripe_customer!(user)
    if user.payment_processor.processor_id.blank?
      recreate_stripe_customer!(user)
    end
  end

  def recreate_stripe_customer!(user)
    stripe_customer = Stripe::Customer.create(
      email: user.email,
      metadata: { user_id: user.id, account_id: user.account_id }
    )
    user.payment_processor.update!(processor_id: stripe_customer.id)
  end
end
