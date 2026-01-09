require 'rails_helper'

RSpec.describe AlertJob, 'per-fingerprint rate limiting bypass', type: :job do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }
  let(:alert_rule) { create(:alert_rule, project: project, rule_type: 'new_issue', enabled: true) }
  let(:issue) { create(:issue, project: project) }

  before do
    ActsAsTenant.current_tenant = account
    # Enable notifications
    project.update!(settings: { 'notifications' => { 'enabled' => true } })
  end

  describe 'PER_FINGERPRINT_ALERT_TYPES' do
    it 'includes new_issue' do
      expect(described_class::PER_FINGERPRINT_ALERT_TYPES).to include('new_issue')
    end

    it 'includes error_frequency' do
      expect(described_class::PER_FINGERPRINT_ALERT_TYPES).to include('error_frequency')
    end

    it 'does not include performance_regression' do
      expect(described_class::PER_FINGERPRINT_ALERT_TYPES).not_to include('performance_regression')
    end

    it 'does not include n_plus_one' do
      expect(described_class::PER_FINGERPRINT_ALERT_TYPES).not_to include('n_plus_one')
    end
  end

  describe '#perform for new_issue' do
    let!(:preference) do
      create(:notification_preference,
        project: project,
        alert_type: 'new_issue',
        frequency: 'every_30_minutes',
        enabled: true,
        last_sent_at: 5.minutes.ago # Would normally block
      )
    end

    it 'bypasses global rate limit for new_issue alerts' do
      # Global rate limit would normally block this (last_sent_at is recent)
      # But per-fingerprint alerts should bypass this check

      slack_service = instance_double(SlackNotificationService)
      allow(SlackNotificationService).to receive(:new).and_return(slack_service)
      allow(slack_service).to receive(:configured?).and_return(false)

      expect {
        described_class.new.perform(
          alert_rule.id,
          'new_issue',
          { 'issue_id' => issue.id, 'fingerprint' => issue.fingerprint }
        )
      }.to change { AlertNotification.count }.by(1)
    end

    it 'does not update global last_sent_at' do
      slack_service = instance_double(SlackNotificationService)
      allow(SlackNotificationService).to receive(:new).and_return(slack_service)
      allow(slack_service).to receive(:configured?).and_return(false)

      original_last_sent_at = preference.last_sent_at

      described_class.new.perform(
        alert_rule.id,
        'new_issue',
        { 'issue_id' => issue.id }
      )

      preference.reload
      expect(preference.last_sent_at).to eq(original_last_sent_at)
    end
  end

  describe '#perform for error_frequency' do
    let!(:alert_rule) { create(:alert_rule, project: project, rule_type: 'error_frequency', enabled: true) }
    let!(:preference) do
      create(:notification_preference,
        project: project,
        alert_type: 'error_frequency',
        frequency: 'every_30_minutes',
        enabled: true,
        last_sent_at: 5.minutes.ago
      )
    end

    it 'bypasses global rate limit for error_frequency alerts' do
      slack_service = instance_double(SlackNotificationService)
      allow(SlackNotificationService).to receive(:new).and_return(slack_service)
      allow(slack_service).to receive(:configured?).and_return(false)

      expect {
        described_class.new.perform(
          alert_rule.id,
          'error_frequency',
          { 'issue_id' => issue.id, 'fingerprint' => issue.fingerprint, 'count' => 10, 'time_window' => 5 }
        )
      }.to change { AlertNotification.count }.by(1)
    end
  end

  describe '#perform for performance_regression' do
    let!(:alert_rule) { create(:alert_rule, project: project, rule_type: 'performance_regression', enabled: true) }
    let!(:preference) do
      create(:notification_preference,
        project: project,
        alert_type: 'performance_regression',
        frequency: 'every_30_minutes',
        enabled: true,
        last_sent_at: 5.minutes.ago # Would block
      )
    end
    let(:perf_event) { create(:performance_event, project: project) }

    it 'respects global rate limit for performance_regression alerts' do
      # Global rate limit should block this
      expect {
        described_class.new.perform(
          alert_rule.id,
          'performance_regression',
          { 'event_id' => perf_event.id, 'duration_ms' => 3000 }
        )
      }.not_to change { AlertNotification.count }
    end

    it 'allows performance_regression when outside rate limit window' do
      preference.update!(last_sent_at: 31.minutes.ago)

      slack_service = instance_double(SlackNotificationService)
      allow(SlackNotificationService).to receive(:new).and_return(slack_service)
      allow(slack_service).to receive(:configured?).and_return(false)

      expect {
        described_class.new.perform(
          alert_rule.id,
          'performance_regression',
          { 'event_id' => perf_event.id, 'duration_ms' => 3000 }
        )
      }.to change { AlertNotification.count }.by(1)
    end
  end

  describe '#perform for n_plus_one' do
    let!(:alert_rule) { create(:alert_rule, project: project, rule_type: 'n_plus_one', enabled: true) }
    let!(:preference) do
      create(:notification_preference,
        project: project,
        alert_type: 'n_plus_one',
        frequency: 'every_30_minutes',
        enabled: true,
        last_sent_at: 5.minutes.ago
      )
    end

    it 'respects global rate limit for n_plus_one alerts' do
      expect {
        described_class.new.perform(
          alert_rule.id,
          'n_plus_one',
          { 'incidents' => [], 'controller_action' => 'TestController#action' }
        )
      }.not_to change { AlertNotification.count }
    end
  end
end
