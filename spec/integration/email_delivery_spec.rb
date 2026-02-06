# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Email Delivery Integration", type: :job do
  # These tests verify that emails are actually queued for delivery,
  # not just that the mailer methods return mail objects.

  before do
    # Ensure we use the :test delivery method so emails are captured in deliveries array
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.deliveries.clear
  end

  describe "QuotaAlertJob email delivery" do
    let(:account) do
      create(:account, :free_plan,
        cached_events_used: 6000, # Over the 5000 free limit
        usage_cached_at: Time.current
      )
    end

    before do
      allow_any_instance_of(Account).to receive(:has_payment_method?).and_return(false)
      allow_any_instance_of(Account).to receive(:active_subscription?).and_return(false)
    end

    context "with confirmed user" do
      let!(:user) { create(:user, :confirmed, account: account) }

      it "delivers quota exceeded email" do
        expect {
          QuotaAlertJob.new.perform
        }.to change { emails_sent.count }.by_at_least(1)

        expect_email_to(user.email)
        expect(last_email.subject).to include("quota")
      end
    end

    context "with OAuth user (no confirmed_at)" do
      let!(:user) { create(:user, :oauth, account: account) }

      it "delivers quota exceeded email to OAuth user" do
        expect {
          QuotaAlertJob.new.perform
        }.to change { emails_sent.count }.by_at_least(1)

        expect_email_to(user.email)
      end
    end

    context "with unconfirmed user" do
      let!(:user) { create(:user, :unconfirmed, account: account) }

      it "does NOT deliver any email" do
        expect {
          QuotaAlertJob.new.perform
        }.not_to change { emails_sent.count }

        expect_no_email_to(user.email)
      end
    end
  end

  describe "WeeklyReportJob email delivery" do
    let(:account) { create(:account, :with_stats) }

    # Use memory store for cache in these tests
    around do |example|
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
      Rails.cache = original_cache
    end

    before do
      Rails.cache.clear
    end

    context "with confirmed user and stats" do
      let!(:user) { create(:user, :confirmed, account: account) }

      it "delivers weekly report email" do
        expect {
          WeeklyReportJob.new.perform(account.id)
        }.to change { emails_sent.count }.by(1)

        expect_email_to(user.email)
        expect(last_email.subject).to include("Weekly Report")
      end
    end

    context "with unconfirmed user" do
      let!(:user) { create(:user, :unconfirmed, account: account) }

      it "does NOT deliver weekly report email" do
        expect {
          WeeklyReportJob.new.perform(account.id)
        }.not_to change { emails_sent.count }

        expect_no_email_to(user.email)
      end
    end

    context "with account with zero stats" do
      let(:account_no_stats) { create(:account, :without_stats) }
      let!(:user) { create(:user, :confirmed, account: account_no_stats) }

      it "does NOT deliver weekly report email" do
        expect {
          WeeklyReportJob.new.perform(account_no_stats.id)
        }.not_to change { emails_sent.count }
      end
    end

    context "with multiple users (mixed confirmation status)" do
      let!(:confirmed_user) { create(:user, :confirmed, account: account, email: "confirmed@example.com") }
      let!(:unconfirmed_user) { create(:user, :unconfirmed, account: account, email: "unconfirmed@example.com") }
      let!(:oauth_user) { create(:user, :oauth, account: account, email: "oauth@example.com") }

      it "delivers only to confirmed and OAuth users" do
        expect {
          WeeklyReportJob.new.perform(account.id)
        }.to change { emails_sent.count }.by(2) # confirmed + oauth

        expect_email_to("confirmed@example.com")
        expect_email_to("oauth@example.com")
        expect_no_email_to("unconfirmed@example.com")
      end
    end
  end

  describe "LifecycleMailer email delivery" do
    let(:account) { create(:account, :on_trial) }

    context "with confirmed user" do
      let!(:user) { create(:user, :confirmed, account: account) }

      it "delivers welcome email" do
        expect {
          LifecycleMailer.welcome(account: account).deliver_now
        }.to change { emails_sent.count }.by(1)

        expect_email_to(user.email)
        expect(last_email.subject).to eq("Welcome to ActiveRabbit")
      end

      it "delivers trial ending email" do
        expect {
          LifecycleMailer.trial_ending_soon(account: account, days_left: 3).deliver_now
        }.to change { emails_sent.count }.by(1)

        expect(last_email.subject).to include("Trial ends in 3 days")
      end

      it "delivers payment failed email" do
        expect {
          LifecycleMailer.payment_failed(account: account, invoice_id: "inv_123").deliver_now
        }.to change { emails_sent.count }.by(1)

        expect(last_email.subject).to include("Payment failed")
      end
    end

    context "with unconfirmed user only" do
      let!(:user) { create(:user, :unconfirmed, account: account) }

      it "does NOT deliver welcome email" do
        result = LifecycleMailer.welcome(account: account)

        # Mailer returns NullMail when no confirmed user found
        expect(result.message).to be_a(ActionMailer::Base::NullMail)
        expect(emails_sent.count).to eq(0)
      end

      it "does NOT deliver trial ending email" do
        result = LifecycleMailer.trial_ending_soon(account: account, days_left: 3)

        expect(result.message).to be_a(ActionMailer::Base::NullMail)
        expect(emails_sent.count).to eq(0)
      end
    end
  end

  describe "AlertMailer email delivery" do
    let(:account) { create(:account) }
    let(:user) { create(:user, :confirmed, account: account) }
    let(:project) { create(:project, account: account, user: user) }
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

    before do
      ActsAsTenant.current_tenant = account
    end

    context "with confirmed project owner" do
      it "delivers performance incident email" do
        expect {
          AlertMailer.performance_incident_opened(project: project, incident: incident).deliver_now
        }.to change { emails_sent.count }.by(1)

        expect_email_to(user.email)
        expect(last_email.subject).to include("Performance")
      end
    end

    context "with unconfirmed project owner" do
      before do
        user.update!(confirmed_at: nil, provider: nil)
      end

      it "does NOT deliver performance incident email" do
        result = AlertMailer.performance_incident_opened(project: project, incident: incident)

        expect(result.message).to be_a(ActionMailer::Base::NullMail)
        expect(emails_sent.count).to eq(0)
      end
    end
  end

  describe "Free plan upgrade reminder delivery" do
    let(:account) do
      create(:account, :free_plan,
        cached_events_used: 6000,
        usage_cached_at: Time.current,
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
    let!(:user) { create(:user, :confirmed, account: account) }

    before do
      allow_any_instance_of(Account).to receive(:has_payment_method?).and_return(false)
      allow_any_instance_of(Account).to receive(:active_subscription?).and_return(false)
    end

    it "delivers free plan upgrade reminder email" do
      expect {
        QuotaAlertJob.new.perform
      }.to change { emails_sent.count }.by_at_least(1)

      expect_email_to(user.email)
      expect(last_email.subject).to include("Upgrade")
    end

    it "includes upgrade messaging in email body" do
      QuotaAlertJob.new.perform

      expect(last_email.body.encoded).to include("Free Plan")
      expect(last_email.body.encoded).to include("Team")
    end
  end
end
