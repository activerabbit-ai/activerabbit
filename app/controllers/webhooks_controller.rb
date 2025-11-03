class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!
  skip_before_action :set_current_tenant
  skip_before_action :set_current_project_from_slug
  skip_before_action :check_onboarding_needed

  def stripe
    payload = request.body.read
    sig = request.env['HTTP_STRIPE_SIGNATURE']
    event = Stripe::Webhook.construct_event(payload, sig, ENV.fetch('STRIPE_SIGNING_SECRET'))

    # Idempotency tracking
    already = WebhookEvent.find_by(provider: 'stripe', event_id: event.id)
    if already&.processed_at
      head :ok and return
    end
    ActiveRecord::Base.transaction do
      WebhookEvent.create!(provider: 'stripe', event_id: event.id)
      StripeEventHandler.new(event: event).call
      WebhookEvent.where(provider: 'stripe', event_id: event.id).update_all(processed_at: Time.current)
    end
    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  end
end
