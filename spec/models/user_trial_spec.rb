require 'rails_helper'

RSpec.describe 'User signup trial', type: :model do
  it 'creates an account with a trial ending in TRIAL_DAYS' do
    user = User.create!(email: 'trial@example.com', password: 'Password1!')
    account = user.account

    expect(account).to be_present
    expect(account.trial_ends_at).to be_within(5.seconds).of(Rails.configuration.x.trial_days.days.from_now)
    expect(account.current_plan).to eq('team')
    expect(account.billing_interval).to eq('month')
  end
end


