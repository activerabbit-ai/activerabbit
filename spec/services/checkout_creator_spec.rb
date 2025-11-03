require 'rails_helper'

RSpec.describe CheckoutCreator do
  let(:account) { User.create!(email: 'buyer@example.com', password: 'Password1!').account }

  before do
    allow(Stripe::Checkout::Session).to receive(:create).and_return(OpenStruct.new(url: 'https://stripe.example/session'))
    allow_any_instance_of(Account).to receive_message_chain(:payment_processor, :processor_id).and_return('cus_123')
    allow_any_instance_of(Account).to receive_message_chain(:payment_processor, :customer).and_return(true)
    allow_any_instance_of(Account).to receive(:set_payment_processor).and_return(true)
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
    described_class.new(account: account, plan: 'team', interval: 'month', ai: true).call
    expect(Stripe::Checkout::Session).to have_received(:create).with(hash_including(line_items: array_including(include(price: 'price_ai_m'))))
  end

  it 'uses AI annual price when interval is year' do
    described_class.new(account: account, plan: 'team', interval: 'year', ai: true).call
    expect(Stripe::Checkout::Session).to have_received(:create).with(hash_including(line_items: array_including(include(price: 'price_ai_y'))))
  end
end
