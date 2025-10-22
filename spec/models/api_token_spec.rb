require 'rails_helper'

RSpec.describe ApiToken, type: :model do
  let(:project) { create(:project) }

  describe '.authenticate' do
    it 'returns token and increments usage when valid and active' do
      token = create(:api_token, project: project)
      result = nil
      expect {
        result = described_class.authenticate(token.token)
      }.to change { token.reload.usage_count }.by(1)
      expect(result).to eq(token)
    end

    it 'returns nil when token missing' do
      expect(described_class.authenticate(nil)).to be_nil
    end
  end

  it '#mask_token masks middle characters' do
    token = create(:api_token, token: 'a' * 64, project: project)
    masked = token.mask_token
    expect(masked).to start_with('aaaaaaaa')
    expect(masked).to end_with('aaaaaaaa')
    expect(masked).to include('********')
  end

  it 'can revoke and reactivate' do
    token = create(:api_token, project: project)
    token.revoke!
    expect(token.active).to eq(false)
    token.activate!
    expect(token.active).to eq(true)
  end
end

