require 'rails_helper'

RSpec.describe AlertJob, type: :job do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:project) { create(:project, account: account, user: user) }
  let(:alert_rule) do
    ActsAsTenant.with_tenant(account) do
      project.alert_rules.create!(
        name: "Test Alert",
        rule_type: "performance_regression",
        threshold_value: 1000,
        time_window_minutes: 5,
        enabled: true
      )
    end
  end
  let!(:preference) do
    ActsAsTenant.with_tenant(account) do
      project.notification_preferences.create!(
        alert_type: "performance_regression",
        enabled: true,
        frequency: "every_2_hours",
        last_sent_at: nil
      )
    end
  end

  before do
    # Enable email notifications for project
    project.update!(settings: {
      "notifications" => {
        "enabled" => true,
        "channels" => { "email" => true }
      }
    })
  end

  describe "#perform" do
    let(:payload) do
      {
        "event_id" => 123,
        "duration_ms" => 5000,
        "target" => "TestController#action"
      }
    end

    context "when notifications are enabled and can send" do
      it "creates an AlertNotification record" do
        # Create a performance event for the test
        ActsAsTenant.with_tenant(account) do
          create(:performance_event, project: project, id: 123, duration_ms: 5000)
        end

        expect {
          described_class.new.perform(alert_rule.id, "performance_regression", payload)
        }.to change { AlertNotification.count }.by(1)
      end

      it "marks the preference as sent" do
        ActsAsTenant.with_tenant(account) do
          create(:performance_event, project: project, id: 123, duration_ms: 5000)
        end

        expect {
          described_class.new.perform(alert_rule.id, "performance_regression", payload)
        }.to change { preference.reload.last_sent_at }.from(nil)
      end
    end

    context "when preference frequency blocks sending" do
      before do
        preference.update!(last_sent_at: 30.minutes.ago)
      end

      it "does not create an AlertNotification" do
        expect {
          described_class.new.perform(alert_rule.id, "performance_regression", payload)
        }.not_to change { AlertNotification.count }
      end

      it "does not update last_sent_at" do
        original_time = preference.last_sent_at

        described_class.new.perform(alert_rule.id, "performance_regression", payload)

        expect(preference.reload.last_sent_at).to eq(original_time)
      end
    end

    context "when preference is nil (no preference record)" do
      before do
        preference.destroy!
      end

      it "does not send and returns early" do
        expect {
          described_class.new.perform(alert_rule.id, "performance_regression", payload)
        }.not_to change { AlertNotification.count }
      end
    end

    context "when notifications are disabled for project" do
      before do
        project.update!(settings: {
          "notifications" => { "enabled" => false }
        })
      end

      it "returns early without sending" do
        expect {
          described_class.new.perform(alert_rule.id, "performance_regression", payload)
        }.not_to change { AlertNotification.count }
      end
    end

    context "race condition prevention with database lock" do
      it "uses with_lock to prevent concurrent sends" do
        ActsAsTenant.with_tenant(account) do
          create(:performance_event, project: project, id: 123, duration_ms: 5000)
        end

        # The lock should prevent duplicate sends
        # We verify by checking that preference.with_lock is called
        expect_any_instance_of(NotificationPreference).to receive(:with_lock).and_call_original

        described_class.new.perform(alert_rule.id, "performance_regression", payload)
      end
    end
  end

  describe "email rate limiting" do
    context "with multiple users in account" do
      let!(:user2) { create(:user, account: account) }
      let!(:user3) { create(:user, account: account) }

      before do
        ActsAsTenant.with_tenant(account) do
          create(:performance_event, project: project, id: 123, duration_ms: 5000)
        end
      end

      it "sends emails with delay between them" do
        # Sleep should be called between emails (index > 0)
        expect_any_instance_of(described_class).to receive(:sleep).with(0.6).at_least(:once)

        described_class.new.perform(alert_rule.id, "performance_regression", {
          "event_id" => 123,
          "duration_ms" => 5000,
          "target" => "TestController#action"
        })
      end
    end
  end
end
