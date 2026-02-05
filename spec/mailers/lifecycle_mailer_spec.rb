# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LifecycleMailer, type: :mailer do
  # NOTE: Lifecycle emails (billing, trial, welcome) are ALWAYS sent regardless
  # of user notification settings. These are critical emails that cannot be disabled.
  # Only requirement: user must have confirmed their email address.

  let(:account) { create(:account, :on_trial) }

  describe "ignores notification settings" do
    let(:account_disabled) do
      create(:account, :on_trial, settings: { "slack_notifications_enabled" => false })
    end
    let!(:user) { create(:user, :confirmed, account: account_disabled) }

    it "sends lifecycle emails regardless of account notification settings" do
      mail = described_class.welcome(account: account_disabled)
      expect(mail).not_to be_nil
      expect(mail.to).to eq([user.email])
    end

    it "sends trial emails regardless of account notification settings" do
      mail = described_class.trial_ending_soon(account: account_disabled, days_left: 3)
      expect(mail).not_to be_nil
      expect(mail.to).to eq([user.email])
    end

    it "sends payment emails regardless of account notification settings" do
      mail = described_class.payment_failed(account: account_disabled, invoice_id: "inv_123")
      expect(mail).not_to be_nil
      expect(mail.to).to eq([user.email])
    end
  end

  describe "email confirmation filtering" do
    shared_examples "skips unconfirmed users" do |method_name, method_args|
      context "with unconfirmed user only" do
        let!(:user) { create(:user, :unconfirmed, account: account) }

        it "returns nil" do
          mail = described_class.public_send(method_name, **method_args.call(account))
          expect(mail).to be_nil
        end
      end

      context "with confirmed user" do
        let!(:user) { create(:user, :confirmed, account: account) }

        it "sends email to confirmed user" do
          mail = described_class.public_send(method_name, **method_args.call(account))
          expect(mail).not_to be_nil
          expect(mail.to).to eq([user.email])
        end
      end

      context "with OAuth user" do
        let!(:user) { create(:user, :oauth, account: account) }

        it "sends email to OAuth user" do
          mail = described_class.public_send(method_name, **method_args.call(account))
          expect(mail).not_to be_nil
          expect(mail.to).to eq([user.email])
        end
      end

      context "with mixed confirmed and unconfirmed users" do
        let!(:unconfirmed_user) { create(:user, :unconfirmed, account: account, email: "unconfirmed@example.com") }
        let!(:confirmed_user) { create(:user, :confirmed, account: account, email: "confirmed@example.com") }

        it "sends email to confirmed user only" do
          mail = described_class.public_send(method_name, **method_args.call(account))
          expect(mail).not_to be_nil
          expect(mail.to).to eq([confirmed_user.email])
        end
      end
    end

    describe "#welcome" do
      include_examples "skips unconfirmed users", :welcome, ->(account) { { account: account } }

      context "with confirmed user" do
        let!(:user) { create(:user, :confirmed, account: account) }

        it "has correct subject" do
          mail = described_class.welcome(account: account)
          expect(mail.subject).to eq("Welcome to ActiveRabbit")
        end
      end
    end

    describe "#activation_tip" do
      include_examples "skips unconfirmed users", :activation_tip, ->(account) { { account: account } }

      context "with confirmed user" do
        let!(:user) { create(:user, :confirmed, account: account) }

        it "has correct subject" do
          mail = described_class.activation_tip(account: account)
          expect(mail.subject).to eq("Ship your first alert")
        end
      end
    end

    describe "#trial_ending_soon" do
      include_examples "skips unconfirmed users", :trial_ending_soon, ->(account) { { account: account, days_left: 3 } }

      context "with confirmed user" do
        let!(:user) { create(:user, :confirmed, account: account) }

        it "includes days left in subject" do
          mail = described_class.trial_ending_soon(account: account, days_left: 3)
          expect(mail.subject).to eq("Trial ends in 3 days")
        end
      end
    end

    describe "#trial_end_today" do
      include_examples "skips unconfirmed users", :trial_end_today, ->(account) { { account: account } }

      context "with confirmed user" do
        let!(:user) { create(:user, :confirmed, account: account) }

        it "has correct subject" do
          mail = described_class.trial_end_today(account: account)
          expect(mail.subject).to eq("Trial ends today")
        end
      end
    end

    describe "#payment_failed" do
      include_examples "skips unconfirmed users", :payment_failed, ->(account) { { account: account, invoice_id: "inv_123" } }

      context "with confirmed user" do
        let!(:user) { create(:user, :confirmed, account: account) }

        it "has correct subject" do
          mail = described_class.payment_failed(account: account, invoice_id: "inv_123")
          expect(mail.subject).to eq("Payment failed — update your card")
        end
      end
    end

    describe "#card_expiring" do
      include_examples "skips unconfirmed users", :card_expiring, ->(account) { { account: account } }

      context "with confirmed user" do
        let!(:user) { create(:user, :confirmed, account: account) }

        it "has correct subject" do
          mail = described_class.card_expiring(account: account)
          expect(mail.subject).to eq("Your card is expiring soon")
        end
      end
    end

    describe "#quota_nudge" do
      include_examples "skips unconfirmed users", :quota_nudge, ->(account) { { account: account, percent: 75 } }

      context "with confirmed user" do
        let!(:user) { create(:user, :confirmed, account: account) }

        it "includes percentage in subject" do
          mail = described_class.quota_nudge(account: account, percent: 75)
          expect(mail.subject).to eq("You're at 75% of your monthly quota")
        end
      end
    end
  end
end
