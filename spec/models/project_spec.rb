require 'rails_helper'

RSpec.describe Project, type: :model do
  subject(:project) { build(:project) }

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:issues).dependent(:destroy) }
    it { is_expected.to have_many(:events).dependent(:destroy) }
    it { is_expected.to have_many(:perf_rollups).dependent(:destroy) }
    it { is_expected.to have_many(:sql_fingerprints).dependent(:destroy) }
    it { is_expected.to have_many(:releases).dependent(:destroy) }
    it { is_expected.to have_many(:api_tokens).dependent(:destroy) }
    it { is_expected.to have_many(:healthchecks).dependent(:destroy) }
    it { is_expected.to have_many(:alert_rules).dependent(:destroy) }
    it { is_expected.to have_many(:alert_notifications).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_presence_of(:environment) }
    it { is_expected.to validate_presence_of(:url) }

    it 'validates URL format' do
      project.url = 'not-a-url'
      expect(project).not_to be_valid
      project.url = 'https://example.com'
      expect(project).to be_valid
    end
  end

  describe '#generate_api_token!' do
    it 'creates a token and returns it' do
      project.save!
      expect { project.generate_api_token! }.to change { project.api_tokens.count }.by(1)
      expect(project.api_token).to be_present
    end
  end

  describe '#slack_webhook_url precedence' do
    it 'prefers ENV over settings' do
      project.settings = { 'slack_webhook_url' => 'https://hooks.slack.com/xxx' }
      ClimateControl.modify("SLACK_WEBHOOK_URL_#{project.slug.upcase}" => 'https://env.slack/abc') do
        expect(project.slack_webhook_url).to eq('https://env.slack/abc')
      end
    end
  end
end

