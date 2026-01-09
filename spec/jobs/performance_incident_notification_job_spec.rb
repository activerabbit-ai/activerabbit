require 'rails_helper'

RSpec.describe PerformanceIncidentNotificationJob, type: :job do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }
  let(:incident) do
    create(:performance_incident,
      project: project,
      target: 'UsersController#index',
      status: 'open',
      severity: 'warning',
      trigger_p95_ms: 900.0,
      threshold_ms: 750.0
    )
  end

  before do
    ActsAsTenant.current_tenant = account
    # Enable notifications
    project.update!(settings: { 'notifications' => { 'enabled' => true } })
  end

  describe '#perform with open notification' do
    context 'when Slack is configured' do
      before do
        project.update!(
          slack_access_token: 'xoxb-test-token',
          slack_channel_id: '#alerts'
        )
        project.update!(settings: project.settings.merge('notifications' => { 'enabled' => true, 'channels' => { 'slack' => true } }))
      end

      it 'sends Slack notification' do
        slack_service = instance_double(SlackNotificationService)
        allow(SlackNotificationService).to receive(:new).and_return(slack_service)
        allow(slack_service).to receive(:send_blocks)

        described_class.new.perform(incident.id, 'open')

        expect(slack_service).to have_received(:send_blocks).with(
          blocks: anything,
          fallback_text: anything
        )
      end

      it 'marks open notification as sent' do
        slack_service = instance_double(SlackNotificationService)
        allow(SlackNotificationService).to receive(:new).and_return(slack_service)
        allow(slack_service).to receive(:send_blocks)

        described_class.new.perform(incident.id, 'open')

        incident.reload
        expect(incident.open_notification_sent).to be true
      end

      it 'does not send duplicate notifications' do
        incident.update!(open_notification_sent: true)

        slack_service = instance_double(SlackNotificationService)
        allow(SlackNotificationService).to receive(:new).and_return(slack_service)
        allow(slack_service).to receive(:send_blocks)

        described_class.new.perform(incident.id, 'open')

        expect(slack_service).not_to have_received(:send_blocks)
      end
    end

    context 'when email is configured' do
      let(:user) { create(:user, account: account) }

      before do
        project.update!(settings: project.settings.merge('notifications' => { 'enabled' => true, 'channels' => { 'email' => true } }))
      end

      it 'sends email notification' do
        expect {
          described_class.new.perform(incident.id, 'open')
        }.to have_enqueued_mail(AlertMailer, :performance_incident_opened)
      end
    end
  end

  describe '#perform with close notification' do
    let(:closed_incident) do
      create(:performance_incident,
        project: project,
        target: 'UsersController#index',
        status: 'closed',
        closed_at: Time.current,
        resolve_p95_ms: 400.0,
        peak_p95_ms: 1000.0
      )
    end

    context 'when Slack is configured' do
      before do
        project.update!(
          slack_access_token: 'xoxb-test-token',
          slack_channel_id: '#alerts'
        )
        project.update!(settings: project.settings.merge('notifications' => { 'enabled' => true, 'channels' => { 'slack' => true } }))
      end

      it 'sends close notification' do
        slack_service = instance_double(SlackNotificationService)
        allow(SlackNotificationService).to receive(:new).and_return(slack_service)
        allow(slack_service).to receive(:send_blocks)

        described_class.new.perform(closed_incident.id, 'close')

        expect(slack_service).to have_received(:send_blocks)
      end

      it 'marks close notification as sent' do
        slack_service = instance_double(SlackNotificationService)
        allow(SlackNotificationService).to receive(:new).and_return(slack_service)
        allow(slack_service).to receive(:send_blocks)

        described_class.new.perform(closed_incident.id, 'close')

        closed_incident.reload
        expect(closed_incident.close_notification_sent).to be true
      end
    end
  end

  describe 'notification content' do
    it 'includes correct fields for open notification' do
      slack_service = instance_double(SlackNotificationService)
      allow(SlackNotificationService).to receive(:new).and_return(slack_service)

      expected_blocks = nil
      allow(slack_service).to receive(:send_blocks) do |args|
        expected_blocks = args[:blocks]
      end

      project.update!(
        slack_access_token: 'xoxb-test-token',
        settings: project.settings.merge('notifications' => { 'enabled' => true, 'channels' => { 'slack' => true } })
      )

      described_class.new.perform(incident.id, 'open')

      # Verify blocks contain expected content
      header_block = expected_blocks.find { |b| b[:type] == 'header' }
      expect(header_block[:text][:text]).to include('Performance Incident OPENED')
    end
  end
end

