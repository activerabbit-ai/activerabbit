require 'rails_helper'

RSpec.describe Account, type: :model do
  subject(:account) { build(:account) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
  end

  # describe '#slack_channel=' do
  #   it 'normalizes channel to start with #' do
  #     account.slack_channel = 'alerts'
  #     expect(account.slack_channel).to eq('#alerts')
  #   end
  # end

  # describe '#slack_notifications_enabled?' do
  #   it 'is false when not configured' do
  #     allow(account).to receive(:slack_webhook_url).and_return(nil)
  #     expect(account.slack_notifications_enabled?).to eq(false)
  #   end
  # end
end
