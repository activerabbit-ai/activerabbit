require 'rails_helper'

RSpec.describe Project, type: :model do
  subject(:project) { build(:project) }

  describe 'associations' do
    it { is_expected.to belong_to(:user).optional }
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
    it { is_expected.to validate_presence_of(:environment) }
    it { is_expected.to validate_presence_of(:url) }

    it 'validates URL format' do
      project.url = 'not-a-url'
      expect(project).not_to be_valid
      project.url = 'https://example.com'
      expect(project).to be_valid
    end

    it 'generates slug from name when slug is not provided' do
      project.slug = nil
      project.name = 'My Test Project'
      project.valid?
      expect(project.slug).to eq('my-test-project')
    end

    it 'is valid without a user (user is optional)' do
      project.user = nil
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
end
