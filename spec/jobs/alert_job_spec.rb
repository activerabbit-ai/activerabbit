require 'rails_helper'

RSpec.describe AlertJob, type: :job do
  # Uses @test_account from spec/support/acts_as_tenant.rb
  let(:account) { @test_account }
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

    # Stub Resend API for email delivery
    stub_request(:post, "https://api.resend.com/emails")
      .to_return(status: 200, body: '{"id": "test-email-id"}', headers: { 'Content-Type' => 'application/json' })
  end

  describe "#perform" do
    let!(:performance_event) do
      ActsAsTenant.with_tenant(account) do
        create(:performance_event, project: project, duration_ms: 5000)
      end
    end

    let(:payload) do
      {
        "event_id" => performance_event.id,
        "duration_ms" => 5000,
        "target" => "TestController#action"
      }
    end

    context "when notifications are enabled and can send" do
      it "creates an AlertNotification record" do
        expect {
          described_class.new.perform(alert_rule.id, "performance_regression", payload)
        }.to change { AlertNotification.count }.by(1)
      end

      it "marks the preference as sent" do
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
        # The lock should prevent duplicate sends
        # We verify by checking that preference.with_lock is called
        expect_any_instance_of(NotificationPreference).to receive(:with_lock).and_call_original

        described_class.new.perform(alert_rule.id, "performance_regression", payload)
      end
    end
  end

  describe "email rate limiting" do
    let!(:performance_event) do
      ActsAsTenant.with_tenant(account) do
        create(:performance_event, project: project, duration_ms: 5000)
      end
    end

    context "with multiple users in account" do
      let!(:user2) { create(:user, account: account) }
      let!(:user3) { create(:user, account: account) }
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

      it "sends emails with delay between them" do
        # Sleep should be called between emails (index > 0)
        expect_any_instance_of(described_class).to receive(:sleep).with(0.6).at_least(:once)

        described_class.new.perform(alert_rule.id, "performance_regression", {
          "event_id" => performance_event.id,
          "duration_ms" => 5000,
          "target" => "TestController#action"
        })
      end
    end
  end

  describe "email confirmation filtering" do
    let!(:performance_event) do
      ActsAsTenant.with_tenant(account) do
        create(:performance_event, project: project, duration_ms: 5000)
      end
    end

    let(:payload) do
      {
        "event_id" => performance_event.id,
        "duration_ms" => 5000,
        "target" => "TestController#action"
      }
    end

    context "with unconfirmed users" do
      let!(:unconfirmed_user) { create(:user, :unconfirmed, account: account, email: "unconfirmed@example.com") }

      it "only sends emails to confirmed users" do
        # Should only receive email for the confirmed user, not the unconfirmed one
        expect(AlertMailer).to receive(:send_alert).with(
          hash_including(to: user.email)
        ).and_call_original

        expect(AlertMailer).not_to receive(:send_alert).with(
          hash_including(to: unconfirmed_user.email)
        )

        described_class.new.perform(alert_rule.id, "performance_regression", payload)
      end
    end

    context "with OAuth user" do
      let!(:oauth_user) { create(:user, :oauth, account: account, email: "oauth@example.com") }

      it "sends emails to OAuth users" do
        # Should receive email for both confirmed and OAuth users
        expect(AlertMailer).to receive(:send_alert).twice.and_call_original

        described_class.new.perform(alert_rule.id, "performance_regression", payload)
      end
    end

    context "when all users are unconfirmed" do
      before do
        user.update!(confirmed_at: nil, provider: nil)
      end

      it "does not send any emails" do
        expect(AlertMailer).not_to receive(:send_alert)

        # Job should still complete successfully (notification record created)
        described_class.new.perform(alert_rule.id, "performance_regression", payload)
      end
    end
  end
end
