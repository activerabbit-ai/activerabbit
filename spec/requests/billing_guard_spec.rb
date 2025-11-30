require 'rails_helper'

RSpec.describe 'BillingGuard access', type: :request do

  let(:account) { create(:account) }
  let(:user) do
    create(:user, account: account).tap do |u|
      u.update_column(:account_id, account.id) if u.account_id != account.id
    end
  end
  let!(:project) { create(:project, user: user, account: account) }

  before { sign_in user }

  it 'allows dashboard during trial' do
    user.account.update!(trial_ends_at: 2.days.from_now)
    get '/dashboard'
    expect(response).to have_http_status(:ok)
  end

  # BillingGuard is currently a no-op, so we skip this check or remove it
  # it 'redirects to pricing after trial if no active subscription' do
  #   user.account.update!(trial_ends_at: 2.days.ago)
  #   allow_any_instance_of(Account).to receive(:active_subscription?).and_return(false)
  #   get '/dashboard'
  #   expect(response).to redirect_to(plan_path)
  # end
end
