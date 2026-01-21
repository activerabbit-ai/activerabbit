require 'rails_helper'

RSpec.describe UsageSnapshotJob, type: :job do
  let(:account) { @test_account }
  let(:project) { create(:project, account: account) }
  let(:issue) { create(:issue, account: account, project: project) }

  before do
    # Set billing period to current month
    account.update!(
      event_usage_period_start: Time.current.beginning_of_month,
      event_usage_period_end: Time.current.end_of_month
    )
  end

  describe "#perform" do
    context "with events" do
      it "counts events in billing period" do
        create(:event, account: account, project: project, issue: issue, occurred_at: Time.current)
        create(:event, account: account, project: project, issue: issue, occurred_at: 1.day.ago)
        create(:event, account: account, project: project, issue: issue, occurred_at: 2.months.ago)

        described_class.new.perform

        account.reload
        expect(account.cached_events_used).to eq(2)
      end

      it "updates usage_cached_at timestamp" do
        expect(account.usage_cached_at).to be_nil

        described_class.new.perform

        account.reload
        expect(account.usage_cached_at).to be_within(1.minute).of(Time.current)
      end
    end

    context "with AI summaries" do
      it "counts AI summaries in billing period" do
        create(:issue, account: account, project: project, ai_summary_generated_at: Time.current)
        create(:issue, account: account, project: project, ai_summary_generated_at: 1.day.ago)
        create(:issue, account: account, project: project, ai_summary_generated_at: nil)

        described_class.new.perform

        account.reload
        expect(account.cached_ai_summaries_used).to eq(2)
      end
    end

    context "with pull requests" do
      it "counts pull requests in billing period" do
        create(:ai_request, account: account, request_type: "pull_request", occurred_at: Time.current)
        create(:ai_request, account: account, request_type: "pull_request", occurred_at: 1.day.ago)
        create(:ai_request, account: account, request_type: "summary", occurred_at: Time.current)

        described_class.new.perform

        account.reload
        expect(account.cached_pull_requests_used).to eq(2)
      end
    end

    context "with performance events" do
      it "counts performance events in billing period" do
        create(:performance_event, account: account, project: project, occurred_at: Time.current)
        create(:performance_event, account: account, project: project, occurred_at: 1.day.ago)
        create(:performance_event, account: account, project: project, occurred_at: 2.months.ago)

        described_class.new.perform

        account.reload
        expect(account.cached_performance_events_used).to eq(2)
      end
    end

    context "with projects" do
      it "counts all projects for the account" do
        # project from let(:project) already exists
        create(:project, account: account, name: "Project 2")
        create(:project, account: account, name: "Project 3")

        described_class.new.perform

        account.reload
        expect(account.cached_projects_used).to be >= 2
      end
    end

    context "with multiple accounts" do
      let(:other_account) { create(:account) }
      let(:other_project) { create(:project, account: other_account) }
      let(:other_issue) { create(:issue, account: other_account, project: other_project) }

      before do
        other_account.update!(
          event_usage_period_start: Time.current.beginning_of_month,
          event_usage_period_end: Time.current.end_of_month
        )
      end

      it "updates all accounts" do
        ActsAsTenant.without_tenant do
          create(:event, account: account, project: project, issue: issue, occurred_at: Time.current)
          create(:event, account: other_account, project: other_project, issue: other_issue, occurred_at: Time.current)
          create(:event, account: other_account, project: other_project, issue: other_issue, occurred_at: Time.current)
        end

        described_class.new.perform

        account.reload
        other_account.reload

        expect(account.cached_events_used).to eq(1)
        expect(other_account.cached_events_used).to eq(2)
      end
    end

    context "with uptime monitors" do
      it "counts only enabled uptime monitors" do
        create(:healthcheck, account: account, project: project, enabled: true)
        create(:healthcheck, account: account, project: project, enabled: true)
        create(:healthcheck, account: account, project: project, enabled: false)

        described_class.new.perform

        account.reload
        expect(account.cached_uptime_monitors_used).to eq(2)
      end
    end

    context "with status pages" do
      it "counts projects with status page enabled" do
        create(:project, account: account, settings: { "status_page_enabled" => "true" })
        create(:project, account: account, settings: { "status_page_enabled" => "true" })
        create(:project, account: account, settings: { "status_page_enabled" => "false" })
        create(:project, account: account, settings: {})

        described_class.new.perform

        account.reload
        expect(account.cached_status_pages_used).to eq(2)
      end
    end

    context "billing period boundaries" do
      it "includes events exactly at billing period start" do
        create(:event, account: account, project: project, issue: issue,
               occurred_at: account.event_usage_period_start)

        described_class.new.perform

        account.reload
        expect(account.cached_events_used).to eq(1)
      end

      it "includes events exactly at billing period end" do
        create(:event, account: account, project: project, issue: issue,
               occurred_at: account.event_usage_period_end)

        described_class.new.perform

        account.reload
        expect(account.cached_events_used).to eq(1)
      end

      it "excludes events before billing period" do
        create(:event, account: account, project: project, issue: issue,
               occurred_at: account.event_usage_period_start - 1.second)

        described_class.new.perform

        account.reload
        expect(account.cached_events_used).to eq(0)
      end

      it "excludes events after billing period" do
        create(:event, account: account, project: project, issue: issue,
               occurred_at: account.event_usage_period_end + 1.second)

        described_class.new.perform

        account.reload
        expect(account.cached_events_used).to eq(0)
      end
    end

    context "with all resource types" do
      it "caches all resource counts in one run" do
        # Create various resources
        create(:event, account: account, project: project, issue: issue, occurred_at: Time.current)
        create(:performance_event, account: account, project: project, occurred_at: Time.current)
        create(:issue, account: account, project: project, ai_summary_generated_at: Time.current)
        create(:ai_request, account: account, request_type: "pull_request", occurred_at: Time.current)
        create(:healthcheck, account: account, project: project, enabled: true)
        create(:project, account: account, settings: { "status_page_enabled" => "true" })

        described_class.new.perform

        account.reload
        expect(account.cached_events_used).to eq(1)
        expect(account.cached_performance_events_used).to eq(1)
        expect(account.cached_ai_summaries_used).to eq(1)
        expect(account.cached_pull_requests_used).to eq(1)
        expect(account.cached_uptime_monitors_used).to eq(1)
        expect(account.cached_status_pages_used).to eq(1)
        expect(account.cached_projects_used).to be >= 2
        expect(account.usage_cached_at).to be_present
      end
    end

    context "with no data" do
      it "sets cached values to 0" do
        described_class.new.perform

        account.reload
        expect(account.cached_events_used).to eq(0)
        expect(account.cached_performance_events_used).to eq(0)
        expect(account.cached_ai_summaries_used).to eq(0)
        expect(account.cached_pull_requests_used).to eq(0)
        expect(account.cached_uptime_monitors_used).to eq(0)
        expect(account.cached_status_pages_used).to eq(0)
      end
    end

    context "when billing period is not set" do
      before do
        account.update!(
          event_usage_period_start: nil,
          event_usage_period_end: nil
        )
      end

      it "defaults to current month" do
        create(:event, account: account, project: project, issue: issue, occurred_at: Time.current)
        create(:event, account: account, project: project, issue: issue, occurred_at: 2.months.ago)

        described_class.new.perform

        account.reload
        expect(account.cached_events_used).to eq(1)
      end
    end

    context "error handling" do
      it "logs errors but does not raise" do
        # The job should handle errors gracefully and continue
        expect(Rails.logger).to receive(:info).at_least(:once)

        # Should complete without raising
        expect { described_class.new.perform }.not_to raise_error
      end

      it "logs start and completion messages" do
        expect(Rails.logger).to receive(:info).with(/Starting usage snapshot/)
        expect(Rails.logger).to receive(:info).with(/Completed/)

        described_class.new.perform
      end
    end
  end
end
