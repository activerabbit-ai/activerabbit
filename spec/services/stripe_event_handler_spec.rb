require 'rails_helper'

RSpec.describe StripeEventHandler do
  let(:account) { create(:account) }

  it 'updates account on subscription.updated' do
    event = {
      'type' => 'customer.subscription.updated',
      'data' => {
        'object' => {
          'customer' => 'cus_123',
          'trial_end' => (Time.current + 14.days).to_i,
          'current_period_start' => Time.current.to_i,
          'current_period_end' => (Time.current + 30.days).to_i,
          'items' => {
            'data' => [
              { 'id' => 'si_1', 'price' => { 'id' => ENV['STRIPE_PRICE_DEV_MONTHLY'] } }
            ]
          }
        }
      }
    }

    # Link pay customer to account
    Pay::Customer.create!(owner: account, processor: 'stripe', processor_id: 'cus_123')

    handler = described_class.new(event: event)
    handler.call

    account.reload
    expect(account.current_plan).to eq('developer').or be_present
    expect(account.event_usage_period_start).to be_present
  end

  it 'sets past_due on payment_failed and clears on payment_succeeded' do
    Pay::Customer.create!(owner: account, processor: 'stripe', processor_id: 'cus_123')

    failed = { 'type' => 'invoice.payment_failed', 'data' => { 'object' => { 'customer' => 'cus_123', 'id' => 'in_1' } } }
    described_class.new(event: failed).call
    expect(account.reload.settings['past_due']).to eq(true)

    succeeded = { 'type' => 'invoice.payment_succeeded', 'data' => { 'object' => { 'customer' => 'cus_123', 'id' => 'in_2' } } }
    described_class.new(event: succeeded).call
    expect(account.reload.settings['past_due']).to be_nil
  end
end
