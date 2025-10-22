require 'rails_helper'

RSpec.describe User, type: :model do
  it 'auto-creates an account on create' do
    user = build(:user, account: nil)
    expect { user.save! }.to change { Account.count }.by(1)
    expect(user.account).to be_present
  end

  it 'responds to needs_onboarding?' do
    user = create(:user)
    expect(user.needs_onboarding?).to eq(true)
    create(:project, user: user, account: user.account)
    expect(user.needs_onboarding?).to eq(false)
  end
end

