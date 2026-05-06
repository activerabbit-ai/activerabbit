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

    it 'validates URL format when URL is present' do
      project.url = 'not-a-url'
      expect(project).not_to be_valid
      project.url = 'https://example.com'
      expect(project).to be_valid
    end

    it 'allows blank URL' do
      project.url = nil
      expect(project).to be_valid
      project.url = ''
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

  describe '#auto_fix_enabled?' do
    before { project.save! }

    it 'returns false by default' do
      expect(project.auto_fix_enabled?).to be false
    end

    it 'returns false without github_repo' do
      project.update!(settings: { "auto_fix" => { "enabled" => true } })
      expect(project.auto_fix_enabled?).to be false
    end

    it 'returns true when enabled with github_repo' do
      project.update!(settings: {
        "github_repo" => "owner/repo",
        "auto_fix" => { "enabled" => true }
      })
      expect(project.auto_fix_enabled?).to be true
    end
  end

  describe '#auto_merge_enabled?' do
    before { project.save! }

    it 'returns false when auto_fix is disabled' do
      project.update!(settings: {
        "github_repo" => "owner/repo",
        "auto_fix" => { "enabled" => false, "auto_merge" => true }
      })
      expect(project.auto_merge_enabled?).to be false
    end

    it 'returns true when both auto_fix and auto_merge are enabled' do
      project.update!(settings: {
        "github_repo" => "owner/repo",
        "auto_fix" => { "enabled" => true, "auto_merge" => true }
      })
      expect(project.auto_merge_enabled?).to be true
    end

    it 'returns false when auto_merge not explicitly enabled' do
      project.update!(settings: {
        "github_repo" => "owner/repo",
        "auto_fix" => { "enabled" => true }
      })
      expect(project.auto_merge_enabled?).to be false
    end
  end

  describe '#auto_merge_skip_ci?' do
    before { project.save! }

    it 'returns false when auto_merge is disabled' do
      project.update!(settings: {
        "github_repo" => "owner/repo",
        "auto_fix" => { "enabled" => true, "auto_merge" => false, "skip_ci" => true }
      })
      expect(project.auto_merge_skip_ci?).to be false
    end

    it 'returns true when all three are enabled' do
      project.update!(settings: {
        "github_repo" => "owner/repo",
        "auto_fix" => { "enabled" => true, "auto_merge" => true, "skip_ci" => true }
      })
      expect(project.auto_merge_skip_ci?).to be true
    end
  end

  describe '#auto_fix_min_severity' do
    before { project.save! }

    it 'defaults to medium' do
      expect(project.auto_fix_min_severity).to eq("medium")
    end

    it 'returns configured value' do
      project.update!(settings: {
        "auto_fix" => { "min_severity" => "high" }
      })
      expect(project.auto_fix_min_severity).to eq("high")
    end
  end
end
