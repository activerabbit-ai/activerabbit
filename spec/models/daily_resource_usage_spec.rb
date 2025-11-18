# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyResourceUsage, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account) }
  end

  describe "validations" do
    subject { build(:daily_resource_usage) }

    it { is_expected.to validate_presence_of(:day) }
    it { is_expected.to validate_uniqueness_of(:day).scoped_to(:account_id) }
  end

  describe ".aggregate_for_account_and_day" do
    let(:account) { create(:account) }
    let(:project) { create(:project, account: account) }
    let(:day) { Date.current }

    before do
      # Create test data
      ActsAsTenant.with_tenant(account) do
        # Create events
        create_list(:event, 5, project: project, account: account, occurred_at: day.to_time)
        create_list(:event, 2, project: project, account: account, occurred_at: (day - 1.day).to_time)

        # Create AI summaries
        create_list(:issue, 3, project: project, account: account,
                    ai_summary: "Test summary", ai_summary_generated_at: day.to_time)
        create(:issue, project: project, account: account,
               ai_summary: "Old summary", ai_summary_generated_at: (day - 1.day).to_time)

        # Create pull request records
        user = create(:user, account: account)
        create_list(:ai_request, 2, account: account, user: user,
                    request_type: "pull_request", occurred_at: day.to_time)
        create(:ai_request, account: account, user: user,
               request_type: "pull_request", occurred_at: (day - 1.day).to_time)

        # Create uptime monitors
        create_list(:healthcheck, 4, project: project, account: account, enabled: true)
        create(:healthcheck, project: project, account: account, enabled: false)
      end
    end

    it "creates a new daily_resource_usage record" do
      expect {
        DailyResourceUsage.aggregate_for_account_and_day(account.id, day)
      }.to change(DailyResourceUsage, :count).by(1)
    end

    it "aggregates errors count for the specific day" do
      usage = DailyResourceUsage.aggregate_for_account_and_day(account.id, day)
      expect(usage.errors_count).to eq(5)
    end

    it "aggregates AI summaries count for the specific day" do
      usage = DailyResourceUsage.aggregate_for_account_and_day(account.id, day)
      expect(usage.ai_summaries_count).to eq(3)
    end

    it "aggregates pull requests count for the specific day" do
      usage = DailyResourceUsage.aggregate_for_account_and_day(account.id, day)
      expect(usage.pull_requests_count).to eq(2)
    end

    it "aggregates active uptime monitors count" do
      usage = DailyResourceUsage.aggregate_for_account_and_day(account.id, day)
      expect(usage.uptime_monitors_count).to eq(4)
    end

    context "when there is no usage" do
      let(:empty_account) { create(:account) }
      let(:empty_day) { Date.current - 10.days }

      it "stores nil for zero counts" do
        usage = DailyResourceUsage.aggregate_for_account_and_day(empty_account.id, empty_day)

        expect(usage.errors_count).to be_nil
        expect(usage.ai_summaries_count).to be_nil
        expect(usage.pull_requests_count).to be_nil
      end
    end

    context "when record already exists" do
      let!(:existing_usage) do
        create(:daily_resource_usage,
               account: account,
               day: day,
               errors_count: 100,
               ai_summaries_count: 50)
      end

      it "updates the existing record" do
        expect {
          DailyResourceUsage.aggregate_for_account_and_day(account.id, day)
        }.not_to change(DailyResourceUsage, :count)
      end

      it "updates the counts" do
        usage = DailyResourceUsage.aggregate_for_account_and_day(account.id, day)
        expect(usage.errors_count).to eq(5)
        expect(usage.ai_summaries_count).to eq(3)
      end
    end

    context "with ActsAsTenant" do
      it "works without setting current tenant" do
        ActsAsTenant.current_tenant = nil

        expect {
          DailyResourceUsage.aggregate_for_account_and_day(account.id, day)
        }.not_to raise_error
      end
    end
  end

  describe ".usage_for_period" do
    let(:account) { create(:account) }
    let(:start_date) { Date.current - 7.days }
    let(:end_date) { Date.current }

    before do
      # Create usage records for different days
      create(:daily_resource_usage,
             account: account,
             day: start_date,
             errors_count: 100,
             ai_summaries_count: 5,
             pull_requests_count: 2,
             uptime_monitors_count: 3,
             status_pages_count: 1)

      create(:daily_resource_usage,
             account: account,
             day: start_date + 3.days,
             errors_count: 200,
             ai_summaries_count: 10,
             pull_requests_count: 3,
             uptime_monitors_count: 4,
             status_pages_count: 1)

      create(:daily_resource_usage,
             account: account,
             day: end_date,
             errors_count: 150,
             ai_summaries_count: 7,
             pull_requests_count: 1,
             uptime_monitors_count: 5,
             status_pages_count: 1)

      # Create a record outside the period
      create(:daily_resource_usage,
             account: account,
             day: start_date - 1.day,
             errors_count: 999,
             ai_summaries_count: 99)
    end

    it "sums errors across the period" do
      result = DailyResourceUsage.usage_for_period(account.id, start_date, end_date)
      expect(result.total_errors).to eq(450) # 100 + 200 + 150
    end

    it "sums AI summaries across the period" do
      result = DailyResourceUsage.usage_for_period(account.id, start_date, end_date)
      expect(result.total_ai_summaries).to eq(22) # 5 + 10 + 7
    end

    it "sums pull requests across the period" do
      result = DailyResourceUsage.usage_for_period(account.id, start_date, end_date)
      expect(result.total_pull_requests).to eq(6) # 2 + 3 + 1
    end

    it "returns max uptime monitors" do
      result = DailyResourceUsage.usage_for_period(account.id, start_date, end_date)
      expect(result.max_uptime_monitors).to eq(5) # max of 3, 4, 5
    end

    it "returns max status pages" do
      result = DailyResourceUsage.usage_for_period(account.id, start_date, end_date)
      expect(result.max_status_pages).to eq(1)
    end

    it "excludes records outside the period" do
      result = DailyResourceUsage.usage_for_period(account.id, start_date, end_date)
      expect(result.total_errors).not_to eq(1449) # Should not include the 999
    end

    context "when no usage in period" do
      let(:empty_account) { create(:account) }

      it "returns zeros using COALESCE" do
        result = DailyResourceUsage.usage_for_period(empty_account.id, start_date, end_date)

        expect(result.total_errors).to eq(0)
        expect(result.total_ai_summaries).to eq(0)
        expect(result.total_pull_requests).to eq(0)
        expect(result.max_uptime_monitors).to eq(0)
        expect(result.max_status_pages).to eq(0)
      end
    end

    context "with null values" do
      before do
        create(:daily_resource_usage,
               account: account,
               day: start_date + 5.days,
               errors_count: nil,
               ai_summaries_count: nil,
               pull_requests_count: nil)
      end

      it "handles null values correctly" do
        result = DailyResourceUsage.usage_for_period(account.id, start_date, end_date)
        expect(result.total_errors).to eq(450) # Still 450, null doesn't affect sum
      end
    end
  end

  describe "#total_resources_used" do
    context "with all values present" do
      let(:usage) do
        build(:daily_resource_usage,
              errors_count: 100,
              ai_summaries_count: 10,
              pull_requests_count: 5,
              uptime_monitors_count: 3,
              status_pages_count: 1)
      end

      it "sums all resource counts" do
        expect(usage.total_resources_used).to eq(119) # 100 + 10 + 5 + 3 + 1
      end
    end

    context "with null values" do
      let(:usage) do
        build(:daily_resource_usage,
              errors_count: nil,
              ai_summaries_count: 10,
              pull_requests_count: nil,
              uptime_monitors_count: 3,
              status_pages_count: nil)
      end

      it "treats nil as 0" do
        expect(usage.total_resources_used).to eq(13) # 0 + 10 + 0 + 3 + 0
      end
    end

    context "with all nil values" do
      let(:usage) do
        build(:daily_resource_usage,
              errors_count: nil,
              ai_summaries_count: nil,
              pull_requests_count: nil,
              uptime_monitors_count: nil,
              status_pages_count: nil)
      end

      it "returns 0" do
        expect(usage.total_resources_used).to eq(0)
      end
    end
  end
end

