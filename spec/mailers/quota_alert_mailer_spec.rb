# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuotaAlertMailer, type: :mailer do
  # NOTE: Quota emails are ALWAYS sent regardless of user notification settings.
  # These are critical billing/usage emails that cannot be disabled.
  # Only requirement: user must have confirmed their email address.

  let(:account) do
    create(:account, :free_plan,
      cached_events_used: 6000,
      usage_cached_at: Time.current
    )
  end

  before do
    allow_any_instance_of(Account).to receive(:has_payment_method?).and_return(false)
    allow_any_instance_of(Account).to receive(:active_subscription?).and_return(false)
  end

  describe "ignores notification settings" do
    let(:account_disabled) do
      create(:account, :free_plan,
        cached_events_used: 4200,
        usage_cached_at: Time.current,
        settings: { "slack_notifications_enabled" => false }
      )
    end
    let!(:user) { create(:user, :confirmed, account: account_disabled) }

    before do
      allow_any_instance_of(Account).to receive(:has_payment_method?).and_return(false)
      allow_any_instance_of(Account).to receive(:active_subscription?).and_return(false)
    end

    it "sends quota warning emails regardless of account notification settings" do
      mail = described_class.warning_80_percent(account_disabled, :events)
      expect(mail).not_to be_nil
      expect(mail.to).to eq([user.email])
    end

    it "sends quota exceeded emails regardless of account notification settings" do
      account_disabled.update!(cached_events_used: 6000)
      mail = described_class.quota_exceeded(account_disabled, :events)
      expect(mail).not_to be_nil
      expect(mail.to).to eq([user.email])
    end
  end

  describe "#warning_80_percent" do
    context "with confirmed user" do
      let!(:user) { create(:user, :confirmed, account: account) }

      it "sends email to confirmed user" do
        account.update!(cached_events_used: 4200) # 84% of 5000
        mail = described_class.warning_80_percent(account, :events)

        expect(mail.to).to eq([user.email])
        expect(mail.subject).to include("84%")
        expect(mail.subject).to include("events")
      end
    end

    context "with unconfirmed user only" do
      let!(:user) { create(:user, :unconfirmed, account: account) }

      it "does not send email" do
        account.update!(cached_events_used: 4200)
        mail = described_class.warning_80_percent(account, :events)

        # When no confirmed user, mailer returns early - NullMail wrapper or nil
        if mail.nil?
          expect(mail).to be_nil
        else
          expect(mail.message).to be_a(ActionMailer::Base::NullMail)
        end
      end
    end
  end

  describe "#warning_90_percent" do
    context "with confirmed user" do
      let!(:user) { create(:user, :confirmed, account: account) }

      it "sends email to confirmed user" do
        account.update!(cached_events_used: 4600) # 92% of 5000
        mail = described_class.warning_90_percent(account, :events)

        expect(mail.to).to eq([user.email])
        expect(mail.subject).to include("92%")
      end
    end

    context "with OAuth user" do
      let!(:user) { create(:user, :oauth, account: account) }

      it "sends email to OAuth user" do
        account.update!(cached_events_used: 4600)
        mail = described_class.warning_90_percent(account, :events)

        expect(mail.to).to eq([user.email])
      end
    end
  end

  describe "#quota_exceeded" do
    context "with confirmed user" do
      let!(:user) { create(:user, :confirmed, account: account) }

      it "sends email with exceeded info" do
        mail = described_class.quota_exceeded(account, :events)

        expect(mail.to).to eq([user.email])
        expect(mail.subject).to include("120%") # 6000/5000 = 120%
      end
    end

    context "with unconfirmed user only" do
      let!(:user) { create(:user, :unconfirmed, account: account) }

      it "does not send email" do
        mail = described_class.quota_exceeded(account, :events)

        # When no confirmed user, mailer returns early - NullMail wrapper or nil
        if mail.nil?
          expect(mail).to be_nil
        else
          expect(mail.message).to be_a(ActionMailer::Base::NullMail)
        end
      end
    end
  end

  describe "#quota_exceeded_reminder" do
    let!(:user) { create(:user, :confirmed, account: account) }

    it "sends reminder email with days over quota" do
      mail = described_class.quota_exceeded_reminder(account, :events, 5)

      expect(mail.to).to eq([user.email])
      expect(mail.subject).to include("events")
    end

    context "with unconfirmed user only" do
      before { user.update!(confirmed_at: nil, provider: nil) }

      it "does not send email" do
        mail = described_class.quota_exceeded_reminder(account, :events, 5)

        # When no confirmed user, mailer returns early - NullMail wrapper or nil
        if mail.nil?
          expect(mail).to be_nil
        else
          expect(mail.message).to be_a(ActionMailer::Base::NullMail)
        end
      end
    end
  end

  describe "#free_plan_upgrade_reminder" do
    let!(:user) { create(:user, :confirmed, account: account) }

    it "sends upgrade reminder email" do
      mail = described_class.free_plan_upgrade_reminder(account, :events, 5)

      expect(mail.to).to eq([user.email])
      expect(mail.subject).to include("Upgrade")
      expect(mail.subject).to include("events")
    end

    it "includes upgrade messaging in body" do
      mail = described_class.free_plan_upgrade_reminder(account, :events, 5)

      expect(mail.body.encoded).to include("Free Plan")
      expect(mail.body.encoded).to include("Team")
      expect(mail.body.encoded).to include("Upgrade")
    end

    it "shows days over quota" do
      mail = described_class.free_plan_upgrade_reminder(account, :events, 7)

      expect(mail.body.encoded).to include("7")
    end

    context "with unconfirmed user only" do
      before { user.update!(confirmed_at: nil, provider: nil) }

      it "does not send email" do
        mail = described_class.free_plan_upgrade_reminder(account, :events, 5)

        # When no confirmed user, mailer returns early - NullMail wrapper or nil
        if mail.nil?
          expect(mail).to be_nil
        else
          expect(mail.message).to be_a(ActionMailer::Base::NullMail)
        end
      end
    end

    context "with OAuth user" do
      let!(:oauth_user) { create(:user, :oauth, account: account, email: "oauth@example.com") }
      before { user.destroy! }

      it "sends email to OAuth user" do
        mail = described_class.free_plan_upgrade_reminder(account, :events, 5)

        expect(mail.to).to eq([oauth_user.email])
      end
    end
  end

  describe "different resource types" do
    let!(:user) { create(:user, :confirmed, account: account) }

    %i[events ai_summaries pull_requests uptime_monitors status_pages].each do |resource_type|
      it "handles #{resource_type}" do
        mail = described_class.warning_80_percent(account, resource_type)

        expect(mail).not_to be_nil
        expect(mail.subject).to include(resource_type.to_s.humanize.downcase)
      end
    end
  end
end
