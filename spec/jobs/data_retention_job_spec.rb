require 'rails_helper'

RSpec.describe DataRetentionJob, type: :job do
  let(:account) { @test_account }
  let(:project) { create(:project, account: account) }
  let(:issue) { create(:issue, account: account, project: project) }

  describe "#perform" do
    context "with events" do
      it "deletes events older than 31 days" do
        old_event = create(:event, account: account, project: project, issue: issue, occurred_at: 32.days.ago)
        recent_event = create(:event, account: account, project: project, issue: issue, occurred_at: 30.days.ago)

        expect { described_class.new.perform }.to change { Event.count }.by(-1)

        expect(Event.exists?(old_event.id)).to be false
        expect(Event.exists?(recent_event.id)).to be true
      end

      it "deletes events exactly 31 days old" do
        boundary_event = create(:event, account: account, project: project, issue: issue, occurred_at: 31.days.ago - 1.minute)
        just_under_event = create(:event, account: account, project: project, issue: issue, occurred_at: 31.days.ago + 1.minute)

        described_class.new.perform

        expect(Event.exists?(boundary_event.id)).to be false
        expect(Event.exists?(just_under_event.id)).to be true
      end

      it "keeps events less than 31 days old" do
        recent_event = create(:event, account: account, project: project, issue: issue, occurred_at: 1.day.ago)
        today_event = create(:event, account: account, project: project, issue: issue, occurred_at: Time.current)

        expect { described_class.new.perform }.not_to change { Event.count }

        expect(Event.exists?(recent_event.id)).to be true
        expect(Event.exists?(today_event.id)).to be true
      end
    end

    context "with performance events" do
      it "deletes performance events older than 31 days" do
        old_perf_event = create(:performance_event, account: account, project: project, occurred_at: 32.days.ago)
        recent_perf_event = create(:performance_event, account: account, project: project, occurred_at: 30.days.ago)

        expect { described_class.new.perform }.to change { PerformanceEvent.count }.by(-1)

        expect(PerformanceEvent.exists?(old_perf_event.id)).to be false
        expect(PerformanceEvent.exists?(recent_perf_event.id)).to be true
      end

      it "deletes performance events exactly 31 days old" do
        boundary_event = create(:performance_event, account: account, project: project, occurred_at: 31.days.ago - 1.minute)
        just_under_event = create(:performance_event, account: account, project: project, occurred_at: 31.days.ago + 1.minute)

        described_class.new.perform

        expect(PerformanceEvent.exists?(boundary_event.id)).to be false
        expect(PerformanceEvent.exists?(just_under_event.id)).to be true
      end

      it "keeps performance events less than 31 days old" do
        recent_perf_event = create(:performance_event, account: account, project: project, occurred_at: 1.day.ago)
        today_perf_event = create(:performance_event, account: account, project: project, occurred_at: Time.current)

        expect { described_class.new.perform }.not_to change { PerformanceEvent.count }

        expect(PerformanceEvent.exists?(recent_perf_event.id)).to be true
        expect(PerformanceEvent.exists?(today_perf_event.id)).to be true
      end
    end

    context "with mixed old and new data" do
      it "deletes both old events and old performance events in one run" do
        # Old records (should be deleted)
        old_event = create(:event, account: account, project: project, issue: issue, occurred_at: 40.days.ago)
        old_perf_event = create(:performance_event, account: account, project: project, occurred_at: 40.days.ago)

        # Recent records (should be kept)
        recent_event = create(:event, account: account, project: project, issue: issue, occurred_at: 5.days.ago)
        recent_perf_event = create(:performance_event, account: account, project: project, occurred_at: 5.days.ago)

        described_class.new.perform

        expect(Event.exists?(old_event.id)).to be false
        expect(PerformanceEvent.exists?(old_perf_event.id)).to be false
        expect(Event.exists?(recent_event.id)).to be true
        expect(PerformanceEvent.exists?(recent_perf_event.id)).to be true
      end
    end

    context "with multiple accounts" do
      let(:other_account) { create(:account) }
      let(:other_project) { create(:project, account: other_account) }
      let(:other_issue) { create(:issue, account: other_account, project: other_project) }

      it "deletes old data from all accounts" do
        # Old records in first account
        old_event1 = ActsAsTenant.without_tenant do
          create(:event, account: account, project: project, issue: issue, occurred_at: 35.days.ago)
        end

        # Old records in second account
        old_event2 = ActsAsTenant.without_tenant do
          create(:event, account: other_account, project: other_project, issue: other_issue, occurred_at: 35.days.ago)
        end

        described_class.new.perform

        ActsAsTenant.without_tenant do
          expect(Event.exists?(old_event1.id)).to be false
          expect(Event.exists?(old_event2.id)).to be false
        end
      end
    end

    context "with large datasets" do
      it "handles batch deletion efficiently" do
        # Create multiple old events
        5.times do
          create(:event, account: account, project: project, issue: issue, occurred_at: 35.days.ago)
          create(:performance_event, account: account, project: project, occurred_at: 35.days.ago)
        end

        # Create recent events
        2.times do
          create(:event, account: account, project: project, issue: issue, occurred_at: 5.days.ago)
          create(:performance_event, account: account, project: project, occurred_at: 5.days.ago)
        end

        described_class.new.perform

        expect(Event.count).to eq(2)
        expect(PerformanceEvent.count).to eq(2)
      end
    end

    context "with no old data" do
      it "completes without errors when there is nothing to delete" do
        create(:event, account: account, project: project, issue: issue, occurred_at: 1.day.ago)
        create(:performance_event, account: account, project: project, occurred_at: 1.day.ago)

        expect { described_class.new.perform }.not_to raise_error
        expect(Event.count).to eq(1)
        expect(PerformanceEvent.count).to eq(1)
      end

      it "completes without errors when tables are empty" do
        expect { described_class.new.perform }.not_to raise_error
      end
    end
  end

  describe "RETENTION_DAYS constant" do
    it "is set to 31 days" do
      expect(DataRetentionJob::RETENTION_DAYS).to eq(31)
    end
  end
end
