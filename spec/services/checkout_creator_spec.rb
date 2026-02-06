require 'rails_helper'
require 'ostruct'

RSpec.describe CheckoutCreator do
  let(:account) { create(:account) }
  let(:user) { create(:user, :confirmed, account: account, email: 'buyer@example.com') }

  before do
    allow(Stripe::Checkout::Session).to receive(:create).and_return(OpenStruct.new(url: 'https://stripe.example/session'))
    # Stub Pay::Customer on the user, since CheckoutCreator talks to @user.payment_processor
    pay_customer = Pay::Customer.create!(owner: user, processor: "stripe", processor_id: "cus_123")
    allow(user).to receive(:payment_processor).and_return(pay_customer)
    allow(user).to receive(:set_payment_processor).with(:stripe).and_return(pay_customer)
    ENV['STRIPE_PRICE_DEV_MONTHLY'] = 'price_dev_m'
    ENV['STRIPE_PRICE_DEV_ANNUAL']  = 'price_dev_y'
    ENV['STRIPE_PRICE_TEAM_MONTHLY'] = 'price_team_m'
    ENV['STRIPE_PRICE_TEAM_ANNUAL']  = 'price_team_y'
    ENV['STRIPE_PRICE_ENT_MONTHLY'] = 'price_ent_m'
    ENV['STRIPE_PRICE_ENT_ANNUAL']  = 'price_ent_y'
    ENV['STRIPE_PRICE_AI_MONTHLY'] = 'price_ai_m'
    ENV['STRIPE_PRICE_AI_ANNUAL']  = 'price_ai_y'
    ENV['STRIPE_PRICE_AI_OVERAGE_METERED'] = 'price_ai_over_m'
    ENV['APP_HOST'] = 'localhost:3000'
  end

  it 'uses AI monthly price when interval is month' do
    described_class.new(user: user, account: account, plan: 'team', interval: 'month', ai: true).call
    expect(Stripe::Checkout::Session).to have_received(:create).with(hash_including(line_items: array_including(include(price: 'price_ai_m'))))
  end

  it 'uses AI annual price when interval is year' do
    described_class.new(user: user, account: account, plan: 'team', interval: 'year', ai: true).call
    expect(Stripe::Checkout::Session).to have_received(:create).with(hash_including(line_items: array_including(include(price: 'price_ai_y'))))
  end
end
