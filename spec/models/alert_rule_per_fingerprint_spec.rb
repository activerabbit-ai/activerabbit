require 'rails_helper'

RSpec.describe AlertRule, 'per-fingerprint rate limiting', type: :model do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }
  let(:redis) { Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/1") }

  before do
    ActsAsTenant.current_tenant = account
  end

  describe '.check_error_frequency_rules' do
    let!(:alert_rule) do
      create(:alert_rule,
        project: project,
        rule_type: 'error_frequency',
        threshold_value: 5,
        time_window_minutes: 10,
        cooldown_minutes: 30,
        enabled: true
      )
    end

    let(:issue) { create(:issue, project: project, fingerprint: 'test-fingerprint-123') }

    before do
      # Create enough events to trigger the rule
      6.times do
        create(:event, issue: issue, project: project, created_at: 5.minutes.ago)
      end

      # Clear Redis
      redis.del("error_freq:#{alert_rule.id}:#{issue.fingerprint}")
    end

    it 'triggers alert when threshold is exceeded' do
      expect {
        described_class.check_error_frequency_rules(issue, rate_limit_minutes: 30)
      }.to change { AlertJob.jobs.size }.by(1)
    end

    it 'includes fingerprint in payload' do
      described_class.check_error_frequency_rules(issue, rate_limit_minutes: 30)

      job = AlertJob.jobs.last
      payload = job['args'][2]

      expect(payload['fingerprint']).to eq(issue.fingerprint)
    end

    it 'sets per-fingerprint rate limit in Redis' do
      described_class.check_error_frequency_rules(issue, rate_limit_minutes: 30)

      expect(redis.exists?("error_freq:#{alert_rule.id}:#{issue.fingerprint}")).to be true
    end

    it 'does not trigger if per-fingerprint rate limited' do
      # Set rate limit
      redis.set("error_freq:#{alert_rule.id}:#{issue.fingerprint}", true, ex: 30.minutes.to_i)

      expect {
        described_class.check_error_frequency_rules(issue, rate_limit_minutes: 30)
      }.not_to change { AlertJob.jobs.size }
    end

    context 'with different fingerprints' do
      let(:issue2) { create(:issue, project: project, fingerprint: 'different-fingerprint') }

      before do
        6.times do
          create(:event, issue: issue2, project: project, created_at: 5.minutes.ago)
        end
      end

      it 'allows alerts for different fingerprints' do
        # Rate limit first issue
        described_class.check_error_frequency_rules(issue, rate_limit_minutes: 30)

        # Second issue should still trigger
        expect {
          described_class.check_error_frequency_rules(issue2, rate_limit_minutes: 30)
        }.to change { AlertJob.jobs.size }.by(1)
      end
    end

    context 'with cooldown' do
      it 'respects cooldown period' do
        # Create a recent alert notification
        create(:alert_notification,
          alert_rule: alert_rule,
          project: project,
          created_at: 20.minutes.ago, # Within 30 min cooldown
          payload: { 'fingerprint' => issue.fingerprint }
        )

        expect {
          described_class.check_error_frequency_rules(issue, rate_limit_minutes: 30)
        }.not_to change { AlertJob.jobs.size }
      end
    end

    context 'with rate_limit_minutes parameter' do
      it 'uses provided rate limit' do
        described_class.check_error_frequency_rules(issue, rate_limit_minutes: 60)

        ttl = redis.ttl("error_freq:#{alert_rule.id}:#{issue.fingerprint}")
        expect(ttl).to be_within(5).of(60.minutes.to_i)
      end

      it 'defaults to 30 minutes' do
        described_class.check_error_frequency_rules(issue)

        ttl = redis.ttl("error_freq:#{alert_rule.id}:#{issue.fingerprint}")
        expect(ttl).to be_within(5).of(30.minutes.to_i)
      end
    end
  end
end
