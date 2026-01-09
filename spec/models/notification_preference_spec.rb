require 'rails_helper'

RSpec.describe NotificationPreference, type: :model do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }

  before do
    ActsAsTenant.current_tenant = account
  end

  describe 'validations' do
    it { is_expected.to validate_inclusion_of(:alert_type).in_array(NotificationPreference::ALERT_TYPES) }
    it { is_expected.to validate_inclusion_of(:frequency).in_array(NotificationPreference::FREQUENCIES) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:project) }
  end

  describe '#rate_limit_minutes' do
    it 'returns 5 for immediate' do
      pref = build(:notification_preference, project: project, frequency: 'immediate')
      expect(pref.rate_limit_minutes).to eq(5)
    end

    it 'returns 30 for every_30_minutes' do
      pref = build(:notification_preference, project: project, frequency: 'every_30_minutes')
      expect(pref.rate_limit_minutes).to eq(30)
    end

    it 'returns 120 for every_2_hours' do
      pref = build(:notification_preference, project: project, frequency: 'every_2_hours')
      expect(pref.rate_limit_minutes).to eq(120)
    end

    it 'returns 30 as default for special frequencies' do
      pref = build(:notification_preference, project: project, frequency: 'first_in_deploy')
      expect(pref.rate_limit_minutes).to eq(30)
    end
  end

  describe '#can_send_now?' do
    context 'when disabled' do
      it 'returns false' do
        pref = build(:notification_preference, project: project, enabled: false)
        expect(pref.can_send_now?).to be false
      end
    end

    context 'when immediate' do
      let(:pref) { build(:notification_preference, project: project, frequency: 'immediate', enabled: true) }

      it 'always returns true' do
        expect(pref.can_send_now?).to be true
      end
    end

    context 'when every_30_minutes' do
      let(:pref) { build(:notification_preference, project: project, frequency: 'every_30_minutes', enabled: true) }

      it 'returns true if never sent' do
        pref.last_sent_at = nil
        expect(pref.can_send_now?).to be true
      end

      it 'returns true if sent more than 30 minutes ago' do
        pref.last_sent_at = 31.minutes.ago
        expect(pref.can_send_now?).to be true
      end

      it 'returns false if sent within 30 minutes' do
        pref.last_sent_at = 29.minutes.ago
        expect(pref.can_send_now?).to be false
      end
    end

    context 'when every_2_hours' do
      let(:pref) { build(:notification_preference, project: project, frequency: 'every_2_hours', enabled: true) }

      it 'returns true if sent more than 2 hours ago' do
        pref.last_sent_at = 121.minutes.ago
        expect(pref.can_send_now?).to be true
      end

      it 'returns false if sent within 2 hours' do
        pref.last_sent_at = 119.minutes.ago
        expect(pref.can_send_now?).to be false
      end
    end

    context 'when first_in_deploy' do
      let(:pref) { build(:notification_preference, project: project, frequency: 'first_in_deploy', enabled: true) }

      it 'returns true (logic handled in IssueAlertJob)' do
        expect(pref.can_send_now?).to be true
      end
    end

    context 'when after_close' do
      let(:pref) { build(:notification_preference, project: project, frequency: 'after_close', enabled: true) }

      it 'returns true (logic handled in IssueAlertJob)' do
        expect(pref.can_send_now?).to be true
      end
    end
  end

  describe '#frequency_description' do
    it 'returns human-readable description for immediate' do
      pref = build(:notification_preference, project: project, frequency: 'immediate')
      expect(pref.frequency_description).to include('immediately')
    end

    it 'returns human-readable description for every_30_minutes' do
      pref = build(:notification_preference, project: project, frequency: 'every_30_minutes')
      expect(pref.frequency_description).to include('30 minutes')
    end

    it 'returns human-readable description for every_2_hours' do
      pref = build(:notification_preference, project: project, frequency: 'every_2_hours')
      expect(pref.frequency_description).to include('2 hours')
    end

    it 'returns human-readable description for first_in_deploy' do
      pref = build(:notification_preference, project: project, frequency: 'first_in_deploy')
      expect(pref.frequency_description).to include('deploy')
    end

    it 'returns human-readable description for after_close' do
      pref = build(:notification_preference, project: project, frequency: 'after_close')
      expect(pref.frequency_description).to include('recur')
    end
  end

  describe '#mark_sent!' do
    it 'updates last_sent_at' do
      pref = create(:notification_preference, project: project, last_sent_at: nil)

      expect {
        pref.mark_sent!
      }.to change { pref.reload.last_sent_at }.from(nil)

      expect(pref.last_sent_at).to be_within(1.second).of(Time.current)
    end
  end
end
