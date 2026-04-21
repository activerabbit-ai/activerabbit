require 'rails_helper'

RSpec.describe AiProviderConfig, type: :model do
  subject(:config) { build(:ai_provider_config) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:provider) }
    it { is_expected.to validate_presence_of(:api_key) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
  end

  describe '#activate!' do
    let(:account) { create(:account) }
    let!(:config_a) { create(:ai_provider_config, account: account, provider: "anthropic", active: true) }
    let!(:config_b) { create(:ai_provider_config, account: account, provider: "openai", active: false) }

    it 'sets self as active and deactivates siblings' do
      config_b.activate!

      expect(config_b.reload).to be_active
      expect(config_a.reload).not_to be_active
    end

    it 'only deactivates configs for the same account' do
      other_account = create(:account)
      other_config = create(:ai_provider_config, account: other_account, provider: "anthropic", active: true)

      config_b.activate!

      expect(other_config.reload).to be_active
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }

    it '.active returns only active configs' do
      active = create(:ai_provider_config, account: account, active: true)
      _inactive = create(:ai_provider_config, account: account, provider: "openai", active: false)

      expect(account.ai_provider_configs.active).to eq([active])
    end
  end
end
