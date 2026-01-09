require 'rails_helper'

RSpec.describe IssueAlertJob, type: :job do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }
  let(:issue) { create(:issue, project: project, fingerprint: 'abc123', count: 1, first_seen_at: Time.current) }
  let(:redis) { Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/1") }

  before do
    ActsAsTenant.current_tenant = account
    # Create default alert rules
    create(:alert_rule, project: project, rule_type: 'new_issue', enabled: true)
    # Create notification preference
    create(:notification_preference, project: project, alert_type: 'new_issue', frequency: 'every_30_minutes', enabled: true)
    # Clear Redis
    redis.del("issue_rate_limit:#{project.id}:new_issue:#{issue.fingerprint}")
  end

  describe '#perform' do
    it 'queues AlertJob for new issues' do
      expect {
        described_class.new.perform(issue.id, account.id)
      }.to change { AlertJob.jobs.size }.by(1)
    end

    it 'does not queue AlertJob if rate limited' do
      # Set rate limit
      redis.set("issue_rate_limit:#{project.id}:new_issue:#{issue.fingerprint}", true, ex: 30.minutes.to_i)

      expect {
        described_class.new.perform(issue.id, account.id)
      }.not_to change { AlertJob.jobs.size }
    end

    it 'sets rate limit after sending alert' do
      described_class.new.perform(issue.id, account.id)

      expect(redis.exists?("issue_rate_limit:#{project.id}:new_issue:#{issue.fingerprint}")).to be true
    end

    context 'with different fingerprints' do
      let(:issue2) { create(:issue, project: project, fingerprint: 'xyz789', count: 1) }

      it 'allows alerts for different fingerprints' do
        described_class.new.perform(issue.id, account.id)

        expect {
          described_class.new.perform(issue2.id, account.id)
        }.to change { AlertJob.jobs.size }.by(1)
      end
    end
  end

  describe '#first_occurrence_in_deploy?' do
    let(:job) { described_class.new }
    let!(:release) { create(:release, project: project, deployed_at: 1.hour.ago) }

    it 'returns true for issues created after deploy' do
      issue.update!(first_seen_at: 30.minutes.ago)

      # The method is private, so we test directly with send
      result = job.send(:first_occurrence_in_deploy?, issue.reload, release)
      expect(result).to be true
    end

    it 'returns false for issues created before deploy' do
      issue.update!(first_seen_at: 2.hours.ago, closed_at: nil)

      result = job.send(:first_occurrence_in_deploy?, issue.reload, release)
      expect(result).to be false
    end

    it 'returns true for issues closed before deploy and reopened' do
      issue.update!(
        first_seen_at: 2.hours.ago,
        closed_at: 90.minutes.ago # Before deploy
      )

      result = job.send(:first_occurrence_in_deploy?, issue.reload, release)
      expect(result).to be true
    end
  end

  describe '#frequency_to_minutes' do
    let(:job) { described_class.new }

    it 'returns 5 minutes for immediate' do
      expect(job.send(:frequency_to_minutes, 'immediate')).to eq(5)
    end

    it 'returns 30 minutes for every_30_minutes' do
      expect(job.send(:frequency_to_minutes, 'every_30_minutes')).to eq(30)
    end

    it 'returns 120 minutes for every_2_hours' do
      expect(job.send(:frequency_to_minutes, 'every_2_hours')).to eq(120)
    end

    it 'returns 30 minutes as default' do
      expect(job.send(:frequency_to_minutes, nil)).to eq(30)
      expect(job.send(:frequency_to_minutes, 'unknown')).to eq(30)
    end
  end

  describe 'first_in_deploy frequency mode' do
    let!(:release) { create(:release, project: project, deployed_at: 1.hour.ago) }

    before do
      project.notification_preferences.find_by(alert_type: 'new_issue')
             .update!(frequency: 'first_in_deploy')
    end

    it 'sends alert for first occurrence in deploy' do
      issue.update!(first_seen_at: 30.minutes.ago)

      expect {
        described_class.new.perform(issue.id, account.id)
      }.to change { AlertJob.jobs.size }.by(1)
    end

    it 'does not send alert for issues before deploy' do
      issue.update!(first_seen_at: 2.hours.ago, closed_at: nil)

      expect {
        described_class.new.perform(issue.id, account.id)
      }.not_to change { AlertJob.jobs.size }
    end
  end

  describe 'after_close frequency mode' do
    before do
      project.notification_preferences.find_by(alert_type: 'new_issue')
             .update!(frequency: 'after_close')
    end

    it 'sends alert for recurring issues (previously closed)' do
      issue.update!(closed_at: 1.hour.ago)

      expect {
        described_class.new.perform(issue.id, account.id)
      }.to change { AlertJob.jobs.size }.by(1)
    end

    it 'does not send alert for new issues (never closed)' do
      issue.update!(closed_at: nil)

      expect {
        described_class.new.perform(issue.id, account.id)
      }.not_to change { AlertJob.jobs.size }
    end
  end
end
