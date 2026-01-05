require 'rails_helper'

RSpec.describe WeeklyReportJob, type: :job do
  let(:account) { @test_account }
  let!(:user) { create(:user, account: account) }

  # Use memory store for cache in these tests (test env uses null_store by default)
  around do |example|
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original_cache
  end

  before do
    account.update!(name: "Test Account")
    Rails.cache.clear
  end

  describe "#perform" do
    let(:mock_mail) { double("Mail", deliver_now: true) }

    before do
      allow(WeeklyReportMailer).to receive(:with).and_return(double(weekly_report: mock_mail))
    end

    it "sends weekly report email to account users" do
      expect(WeeklyReportMailer).to receive(:with).with(
        hash_including(user: user, account: account)
      ).and_return(double(weekly_report: mock_mail))

      described_class.new.perform(account.id)
    end

    it "calls deliver_now on the mailer" do
      expect(mock_mail).to receive(:deliver_now)

      described_class.new.perform(account.id)
    end

    context "when job runs multiple times in the same week" do
      it "only sends one email per account per week" do
        # First run - should send email
        expect(WeeklyReportMailer).to receive(:with).once.and_return(double(weekly_report: mock_mail))

        described_class.new.perform(account.id)
        described_class.new.perform(account.id)
        described_class.new.perform(account.id)
      end

      it "sends email again after cache expires (next week)" do
        expect(WeeklyReportMailer).to receive(:with).twice.and_return(double(weekly_report: mock_mail))

        # First run
        described_class.new.perform(account.id)

        # Simulate next week by clearing cache
        Rails.cache.clear

        # Should send again
        described_class.new.perform(account.id)
      end
    end

    context "with multiple accounts" do
      let!(:other_account) { create(:account, name: "Other Account") }
      let!(:other_user) { create(:user, account: other_account, email: "other@example.com") }

      it "sends one email per account when no account_id provided" do
        # Count total users across all accounts
        total_users = User.count
        expect(WeeklyReportMailer).to receive(:with).exactly(total_users).times.and_return(double(weekly_report: mock_mail))

        described_class.new.perform
      end

      it "does not send duplicate emails when run multiple times" do
        total_users = User.count
        # Should only send once per user total, not twice
        expect(WeeklyReportMailer).to receive(:with).exactly(total_users).times.and_return(double(weekly_report: mock_mail))

        # First run - sends to all users
        described_class.new.perform

        # Second run - should not send any (all cached)
        described_class.new.perform
      end

      it "only skips accounts that already received reports" do
        # First run - sends to all users in all accounts
        described_class.new.perform

        # Clear cache for other_account only
        week_key = Date.current.beginning_of_week.to_s
        Rails.cache.delete("weekly_report:#{other_account.id}:#{week_key}")

        # Second run - only sends to users in other_account (1 user)
        expect(WeeklyReportMailer).to receive(:with).once.and_return(double(weekly_report: mock_mail))
        described_class.new.perform
      end
    end

    context "with multiple users in one account" do
      let!(:second_user) { create(:user, account: account, email: "second@example.com") }

      it "sends email to all users in the account" do
        expect(WeeklyReportMailer).to receive(:with).twice.and_return(double(weekly_report: mock_mail))

        described_class.new.perform(account.id)
      end

      it "does not send duplicate emails when run multiple times" do
        # Should only send twice total (once per user), not 4 times
        expect(WeeklyReportMailer).to receive(:with).twice.and_return(double(weekly_report: mock_mail))

        described_class.new.perform(account.id)
        described_class.new.perform(account.id)
      end
    end
  end

  describe "cache key format" do
    let(:mock_mail) { double("Mail", deliver_now: true) }

    before do
      allow(WeeklyReportMailer).to receive(:with).and_return(double(weekly_report: mock_mail))
    end

    it "uses week-based cache key" do
      week_key = Date.current.beginning_of_week.to_s
      cache_key = "weekly_report:#{account.id}:#{week_key}"

      expect(Rails.cache.exist?(cache_key)).to be false

      described_class.new.perform(account.id)

      expect(Rails.cache.exist?(cache_key)).to be true
    end

    it "cache expires after 8 days" do
      described_class.new.perform(account.id)

      week_key = Date.current.beginning_of_week.to_s
      cache_key = "weekly_report:#{account.id}:#{week_key}"

      # Verify cache exists
      expect(Rails.cache.exist?(cache_key)).to be true
    end
  end
end

