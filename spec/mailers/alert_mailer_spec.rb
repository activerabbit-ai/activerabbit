require 'rails_helper'

RSpec.describe AlertMailer, type: :mailer do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user) }

  before do
    ActsAsTenant.current_tenant = account
  end

  describe '#performance_incident_opened' do
    let(:incident) do
      create(:performance_incident,
        project: project,
        target: 'UsersController#index',
        status: 'open',
        severity: 'warning',
        trigger_p95_ms: 900.0,
        threshold_ms: 750.0,
        environment: 'production'
      )
    end

    it 'sends email to project recipients' do
      mail = described_class.performance_incident_opened(project: project, incident: incident)

      expect(mail.to).to include(user.email)
    end

    it 'includes warning emoji for warning severity' do
      mail = described_class.performance_incident_opened(project: project, incident: incident)

      expect(mail.subject).to include('🟡')
      expect(mail.subject).to include('WARNING')
    end

    it 'includes critical emoji for critical severity' do
      incident.update!(severity: 'critical')
      mail = described_class.performance_incident_opened(project: project, incident: incident)

      expect(mail.subject).to include('🔴')
      expect(mail.subject).to include('CRITICAL')
    end

    it 'includes endpoint in subject' do
      mail = described_class.performance_incident_opened(project: project, incident: incident)

      expect(mail.subject).to include('UsersController#index')
    end

    it 'includes p95 metrics in body' do
      mail = described_class.performance_incident_opened(project: project, incident: incident)

      expect(mail.body.encoded).to include('900')
      expect(mail.body.encoded).to include('750')
    end
  end

  describe '#performance_incident_resolved' do
    let(:incident) do
      create(:performance_incident,
        project: project,
        target: 'UsersController#index',
        status: 'closed',
        severity: 'warning',
        trigger_p95_ms: 900.0,
        peak_p95_ms: 1100.0,
        resolve_p95_ms: 400.0,
        threshold_ms: 750.0,
        opened_at: 30.minutes.ago,
        closed_at: Time.current,
        environment: 'production'
      )
    end

    it 'includes resolved emoji' do
      mail = described_class.performance_incident_resolved(project: project, incident: incident)

      expect(mail.subject).to include('✅')
    end

    it 'includes recovery info in body' do
      mail = described_class.performance_incident_resolved(project: project, incident: incident)

      expect(mail.body.encoded).to include('resolved')
    end

    it 'includes duration' do
      mail = described_class.performance_incident_resolved(project: project, incident: incident)

      expect(mail.body.encoded).to include('30')
    end

    it 'includes peak p95' do
      mail = described_class.performance_incident_resolved(project: project, incident: incident)

      expect(mail.body.encoded).to include('1100')
    end
  end

  describe '#send_alert' do
    let(:issue) { create(:issue, project: project) }

    it 'sends alert email' do
      mail = described_class.send_alert(
        to: user.email,
        subject: 'Test Alert',
        body: 'Test body content',
        project: project
      )

      expect(mail.to).to eq([user.email])
      expect(mail.subject).to eq('Test Alert')
    end

    it 'uses provided dashboard URL' do
      mail = described_class.send_alert(
        to: user.email,
        subject: 'Test Alert',
        body: 'Test body',
        project: project,
        dashboard_url: 'https://example.com/dashboard'
      )

      expect(mail.body.encoded).to include('https://example.com/dashboard')
    end
  end
end
