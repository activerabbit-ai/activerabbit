# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuotaAlertJob, type: :job do
  # NOTE: Quota alerts are ALWAYS sent regardless of user notification settings.
  # These are critical billing/usage emails that cannot be disabled.
  # Only requirement: user must have confirmed their email address.

  let(:account) { create(:account, :with_stats) }
  let!(:user) { create(:user, :confirmed, account: account) }

  describe "#perform" do
    it "checks quotas for all accounts" do
      create(:account, :with_stats)
      expect(Account).to receive(:find_each).and_call_original

      described_class.new.perform
    end
  end

  describe "Free plan upgrade reminder frequency" do
    let(:free_account) do
      create(:account, :free_plan,
        cached_events_used: 6000, # Over the 5000 free limit
        usage_cached_at: Time.current
      )
    end
    let!(:free_user) { create(:user, :confirmed, account: free_account) }

    before do
      # Stub has_payment_method? to return false for free plan behavior
      allow_any_instance_of(Account).to receive(:has_payment_method?).and_return(false)
      allow_any_instance_of(Account).to receive(:active_subscription?).and_return(false)
    end

    context "when Free plan account exceeds quota for the first time" do
      it "sends quota_exceeded email" do
        expect(QuotaAlertMailer).to receive(:quota_exceeded)
          .with(free_account, :events)
          .and_return(double(deliver_now: true))

        described_class.new.perform
      end
    end

    context "when Free plan account has been over quota" do
      before do
        free_account.update!(
          last_quota_alert_sent_at: {
            "events" => {
              "sent_at" => 3.days.ago.iso8601,
              "level" => "exceeded",
              "percentage" => 120.0,
              "first_exceeded_at" => 5.days.ago.iso8601
            }
          }
        )
      end

      it "sends free_plan_upgrade_reminder every 2 days" do
        expect(QuotaAlertMailer).to receive(:free_plan_upgrade_reminder)
          .with(free_account, :events, anything)
          .and_return(double(deliver_now: true))

        described_class.new.perform
      end
    end

    context "when Free plan account was alerted less than 2 days ago" do
      before do
        free_account.update!(
          last_quota_alert_sent_at: {
            "events" => {
              "sent_at" => 1.day.ago.iso8601,
              "level" => "exceeded",
              "percentage" => 120.0,
              "first_exceeded_at" => 3.days.ago.iso8601
            }
          }
        )
      end

      it "does not send another reminder" do
        expect(QuotaAlertMailer).not_to receive(:free_plan_upgrade_reminder)
        expect(QuotaAlertMailer).not_to receive(:quota_exceeded)

        described_class.new.perform
      end
    end
  end

  describe "Team/Business plan reminder frequency" do
    let(:team_account) do
      create(:account, :team_plan, :on_trial,
        cached_events_used: 60000, # Over the 50000 team limit
        usage_cached_at: Time.current
      )
    end
    let!(:team_user) { create(:user, :confirmed, account: team_account) }

    context "when paid plan account has been over quota for 3+ days" do
      before do
        team_account.update!(
          last_quota_alert_sent_at: {
            "events" => {
              "sent_at" => 4.days.ago.iso8601,
              "level" => "exceeded",
              "percentage" => 120.0,
              "first_exceeded_at" => 5.days.ago.iso8601
            }
          }
        )
      end

      it "sends quota_exceeded_reminder every 3 days" do
        expect(QuotaAlertMailer).to receive(:quota_exceeded_reminder)
          .with(team_account, :events, anything)
          .and_return(double(deliver_now: true))

        described_class.new.perform
      end
    end

    context "when paid plan account was alerted 2 days ago" do
      before do
        team_account.update!(
          last_quota_alert_sent_at: {
            "events" => {
              "sent_at" => 2.days.ago.iso8601,
              "level" => "exceeded",
              "percentage" => 120.0,
              "first_exceeded_at" => 3.days.ago.iso8601
            }
          }
        )
      end

      it "does not send another reminder (waits 3 days)" do
        expect(QuotaAlertMailer).not_to receive(:quota_exceeded_reminder)

        described_class.new.perform
      end
    end
  end

  describe "warning levels" do
    let(:account_80) do
      create(:account,
        cached_events_used: 4200, # 84% of 5000 free limit
        usage_cached_at: Time.current,
        current_plan: "free",
        trial_ends_at: 1.day.ago
      )
    end
    let!(:user_80) { create(:user, :confirmed, account: account_80) }

    let(:account_90) do
      create(:account,
        cached_events_used: 4600, # 92% of 5000 free limit
        usage_cached_at: Time.current,
        current_plan: "free",
        trial_ends_at: 1.day.ago
      )
    end
    let!(:user_90) { create(:user, :confirmed, account: account_90) }

    before do
      allow_any_instance_of(Account).to receive(:has_payment_method?).and_return(false)
      allow_any_instance_of(Account).to receive(:active_subscription?).and_return(false)
    end

    it "sends 80% warning for accounts at 80-89%" do
      expect(QuotaAlertMailer).to receive(:warning_80_percent)
        .with(account_80, :events)
        .and_return(double(deliver_now: true))

      described_class.new.perform
    end

    it "sends 90% warning for accounts at 90-99%" do
      expect(QuotaAlertMailer).to receive(:warning_90_percent)
        .with(account_90, :events)
        .and_return(double(deliver_now: true))

      described_class.new.perform
    end

    context "when level escalates from 80% to 90%" do
      before do
        account_90.update!(
          last_quota_alert_sent_at: {
            "events" => {
              "sent_at" => 1.hour.ago.iso8601,
              "level" => "80_percent",
              "percentage" => 82.0
            }
          }
        )
      end

      it "sends 90% warning immediately" do
        expect(QuotaAlertMailer).to receive(:warning_90_percent)
          .with(account_90, :events)
          .and_return(double(deliver_now: true))

        described_class.new.perform
      end
    end
  end

  describe "email confirmation check" do
    let(:account_over_quota) do
      create(:account,
        cached_events_used: 6000,
        usage_cached_at: Time.current,
        current_plan: "free",
        trial_ends_at: 1.day.ago
      )
    end

    before do
      allow_any_instance_of(Account).to receive(:has_payment_method?).and_return(false)
      allow_any_instance_of(Account).to receive(:active_subscription?).and_return(false)
    end

    context "when account has no confirmed users" do
      let!(:unconfirmed_user) { create(:user, :unconfirmed, account: account_over_quota) }

      it "mailer returns nil or NullMail and does not send" do
        # The mailer should return early when no confirmed user found
        mail = QuotaAlertMailer.quota_exceeded(account_over_quota, :events)

        # ActionMailer wraps early returns in NullMail
        if mail.nil?
          expect(mail).to be_nil
        else
          expect(mail.message).to be_a(ActionMailer::Base::NullMail)
        end
      end
    end

    context "when account has confirmed user" do
      let!(:confirmed_user) { create(:user, :confirmed, account: account_over_quota) }

      it "sends email to confirmed user" do
        mail = QuotaAlertMailer.quota_exceeded(account_over_quota, :events)
        expect(mail).not_to be_nil
        expect(mail.to).to include(confirmed_user.email)
      end
    end

    context "when account has OAuth user" do
      let!(:oauth_user) { create(:user, :oauth, account: account_over_quota) }

      it "sends email to OAuth user" do
        mail = QuotaAlertMailer.quota_exceeded(account_over_quota, :events)
        expect(mail).not_to be_nil
        expect(mail.to).to include(oauth_user.email)
      end
    end
  end

  describe "ignores user notification settings" do
    # Quota alerts are ALWAYS sent regardless of any notification settings.
    # This is critical billing functionality that cannot be disabled.

    let(:account_with_disabled_notifications) do
      create(:account,
        cached_events_used: 6000,
        usage_cached_at: Time.current,
        current_plan: "free",
        trial_ends_at: 1.day.ago,
        settings: { "slack_notifications_enabled" => false }
      )
    end
    let!(:user_disabled) { create(:user, :confirmed, account: account_with_disabled_notifications) }

    before do
      allow_any_instance_of(Account).to receive(:has_payment_method?).and_return(false)
      allow_any_instance_of(Account).to receive(:active_subscription?).and_return(false)
    end

    it "sends quota alerts even when account notifications are disabled" do
      expect(QuotaAlertMailer).to receive(:quota_exceeded)
        .with(account_with_disabled_notifications, :events)
        .and_return(double(deliver_now: true))

      described_class.new.perform
    end

    context "with project that has notifications disabled" do
      let!(:project) do
        ActsAsTenant.with_tenant(account_with_disabled_notifications) do
          create(:project,
            account: account_with_disabled_notifications,
            user: user_disabled,
            settings: { "notifications" => { "enabled" => false } }
          )
        end
      end

      it "still sends quota alerts (project settings do not affect account-level emails)" do
        expect(QuotaAlertMailer).to receive(:quota_exceeded)
          .with(account_with_disabled_notifications, :events)
          .and_return(double(deliver_now: true))

        described_class.new.perform
      end
    end
  end
end
