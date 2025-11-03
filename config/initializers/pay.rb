# Pay gem configuration
# Configure Stripe API keys via environment variables:
# STRIPE_PUBLIC_KEY
# STRIPE_SECRET_KEY
# STRIPE_SIGNING_SECRET

# Basic Pay configuration
Pay.application_name = 'ActiveRabbit'
Pay.business_name = 'ActiveRabbit'

# Pay v8 does not expose Pay.configure in the same way; keep minimal globals only

Stripe.api_key = ENV['STRIPE_SECRET_KEY'] if ENV['STRIPE_SECRET_KEY'].present?

# STI disabled in app/models/pay/customer.rb
