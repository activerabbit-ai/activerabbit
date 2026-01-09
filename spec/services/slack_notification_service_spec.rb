require 'rails_helper'

RSpec.describe SlackNotificationService, type: :service do
  let(:account) { create(:account) }
  let(:project) do
    create(:project,
      account: account,
      slack_access_token: 'xoxb-test-token',
      slack_channel_id: '#alerts',
      slack_team_name: 'Test Team'
    )
  end
  let(:service) { described_class.new(project) }

  before do
    ActsAsTenant.current_tenant = account
  end

  describe '#configured?' do
    it 'returns true when token is present' do
      expect(service.configured?).to be true
    end

    it 'returns false when token is missing' do
      project.update!(slack_access_token: nil)
      service = described_class.new(project)
      expect(service.configured?).to be false
    end
  end

  describe '#send_blocks' do
    let(:slack_client) { instance_double(Slack::Web::Client) }

    before do
      allow(Slack::Web::Client).to receive(:new).and_return(slack_client)
    end

    it 'sends message with blocks' do
      blocks = [
        { type: 'header', text: { type: 'plain_text', text: 'Test Header' } },
        { type: 'section', text: { type: 'mrkdwn', text: 'Test content' } }
      ]

      expect(slack_client).to receive(:chat_postMessage).with(
        hash_including(
          channel: '#alerts',
          blocks: blocks,
          text: 'Fallback text'
        )
      )

      service.send_blocks(blocks: blocks, fallback_text: 'Fallback text')
    end

    it 'includes username and icon' do
      expect(slack_client).to receive(:chat_postMessage).with(
        hash_including(
          username: 'Test Team',
          icon_emoji: ':rabbit:'
        )
      )

      service.send_blocks(blocks: [], fallback_text: 'Test')
    end

    it 'handles Slack API errors gracefully' do
      allow(slack_client).to receive(:chat_postMessage)
        .and_raise(Slack::Web::Api::Errors::SlackError.new('channel_not_found'))

      expect(Rails.logger).to receive(:error).with(/Failed to send Slack blocks message/)

      service.send_blocks(blocks: [], fallback_text: 'Test')
    end

    it 'does nothing when not configured' do
      project.update!(slack_access_token: nil)
      service = described_class.new(project)

      expect(slack_client).not_to receive(:chat_postMessage)

      service.send_blocks(blocks: [], fallback_text: 'Test')
    end
  end

  describe '#send_new_issue_alert' do
    let(:issue) { create(:issue, project: project) }
    let(:slack_client) { instance_double(Slack::Web::Client) }

    before do
      allow(Slack::Web::Client).to receive(:new).and_return(slack_client)
      allow(slack_client).to receive(:chat_postMessage)
    end

    it 'sends new issue alert' do
      expect(slack_client).to receive(:chat_postMessage).with(
        hash_including(
          text: /New Issue/
        )
      )

      service.send_new_issue_alert(issue)
    end

    it 'includes issue details' do
      expect(slack_client).to receive(:chat_postMessage) do |params|
        attachments = params[:attachments]
        fields = attachments.first[:fields]

        expect(fields.find { |f| f[:title] == 'Exception' }[:value]).to eq(issue.exception_class)
        expect(fields.find { |f| f[:title] == 'Project' }[:value]).to eq(project.name)
      end

      service.send_new_issue_alert(issue)
    end
  end

  describe '#send_error_frequency_alert' do
    let(:issue) { create(:issue, project: project) }
    let(:payload) { { 'count' => 10, 'time_window' => 5 } }
    let(:slack_client) { instance_double(Slack::Web::Client) }

    before do
      allow(Slack::Web::Client).to receive(:new).and_return(slack_client)
      allow(slack_client).to receive(:chat_postMessage)
    end

    it 'includes frequency information' do
      expect(slack_client).to receive(:chat_postMessage) do |params|
        attachments = params[:attachments]
        fields = attachments.first[:fields]
        frequency_field = fields.find { |f| f[:title] == 'Frequency' }

        expect(frequency_field[:value]).to include('10 occurrences')
        expect(frequency_field[:value]).to include('5 minutes')
      end

      service.send_error_frequency_alert(issue, payload)
    end
  end
end

