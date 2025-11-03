require 'rails_helper'

RSpec.describe 'BillingGuard access', type: :request do
  let!(:user) { User.create!(email: 'guard@example.com', password: 'Password1!') }

  before { sign_in user }

  it 'allows dashboard during trial' do
    user.account.update!(trial_ends_at: 2.days.from_now)
    get '/dashboard'
    expect(response).to have_http_status(:ok)
  end

  it 'redirects to pricing after trial if no active subscription' do
    user.account.update!(trial_ends_at: 2.days.ago)
    allow_any_instance_of(Account).to receive(:active_subscription?).and_return(false)
    get '/dashboard'
    expect(response).to redirect_to(pricing_path)
  end
end
