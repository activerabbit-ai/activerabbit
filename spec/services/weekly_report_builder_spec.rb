require 'rails_helper'

RSpec.describe WeeklyReportBuilder do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }
  let(:issue) { create(:issue, project: project) }

  before do
    ActsAsTenant.current_tenant = account
  end

  describe '#initialize' do
    it 'sets the period to previous calendar week (Mon-Sun)' do
      # Freeze time to a known date (Wednesday Jan 15, 2025)
      travel_to Time.zone.local(2025, 1, 15, 10, 0, 0) do
        builder = described_class.new(account)
        report = builder.build

        # Previous week should be Mon Jan 6 to Sun Jan 12
        expect(report[:period].first).to eq(Time.zone.local(2025, 1, 6, 0, 0, 0))
        expect(report[:period].last.to_date).to eq(Date.new(2025, 1, 12))
        expect(report[:period].last.hour).to eq(23)
        expect(report[:period].last.min).to eq(59)
      end
    end

    it 'covers exactly 7 days (Mon through Sun)' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do # Monday
        builder = described_class.new(account)
        report = builder.build

        period_start = report[:period].first.to_date
        period_end = report[:period].last.to_date

        # Should be exactly 7 days (6 days difference between Mon and Sun)
        expect(period_end - period_start).to eq(6)
        expect(period_start.monday?).to be true
        expect(period_end.sunday?).to be true
      end
    end

    it 'reports previous week when run on Monday' do
      # When the job runs Monday morning, it should report the previous Mon-Sun
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do # Monday Jan 20
        builder = described_class.new(account)
        report = builder.build

        # Should report Mon Jan 13 to Sun Jan 19
        expect(report[:period].first.to_date).to eq(Date.new(2025, 1, 13))
        expect(report[:period].last.to_date).to eq(Date.new(2025, 1, 19))
      end
    end
  end

  describe '#errors_by_day' do
    it 'returns all 7 days of the week even with no events' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        builder = described_class.new(account)
        report = builder.build

        expect(report[:errors_by_day].keys.count).to eq(7)
        expect(report[:errors_by_day].values).to all(eq(0))
      end
    end

    it 'returns days in order from Monday to Sunday' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        builder = described_class.new(account)
        report = builder.build

        days = report[:errors_by_day].keys
        expect(days[0].strftime('%A')).to eq('Monday')
        expect(days[1].strftime('%A')).to eq('Tuesday')
        expect(days[2].strftime('%A')).to eq('Wednesday')
        expect(days[3].strftime('%A')).to eq('Thursday')
        expect(days[4].strftime('%A')).to eq('Friday')
        expect(days[5].strftime('%A')).to eq('Saturday')
        expect(days[6].strftime('%A')).to eq('Sunday')
      end
    end

    it 'counts events correctly per day' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        # Create events on specific days of previous week
        # Monday Jan 13: 3 events
        3.times do
          create(:event, account: account, project: project, issue: issue,
                 occurred_at: Time.zone.local(2025, 1, 13, 12, 0, 0))
        end

        # Wednesday Jan 15: 2 events
        2.times do
          create(:event, account: account, project: project, issue: issue,
                 occurred_at: Time.zone.local(2025, 1, 15, 14, 0, 0))
        end

        # Sunday Jan 19: 1 event
        create(:event, account: account, project: project, issue: issue,
               occurred_at: Time.zone.local(2025, 1, 19, 18, 0, 0))

        builder = described_class.new(account)
        report = builder.build

        errors_by_day = report[:errors_by_day]

        expect(errors_by_day[Date.new(2025, 1, 13)]).to eq(3) # Monday
        expect(errors_by_day[Date.new(2025, 1, 14)]).to eq(0) # Tuesday
        expect(errors_by_day[Date.new(2025, 1, 15)]).to eq(2) # Wednesday
        expect(errors_by_day[Date.new(2025, 1, 16)]).to eq(0) # Thursday
        expect(errors_by_day[Date.new(2025, 1, 17)]).to eq(0) # Friday
        expect(errors_by_day[Date.new(2025, 1, 18)]).to eq(0) # Saturday
        expect(errors_by_day[Date.new(2025, 1, 19)]).to eq(1) # Sunday
      end
    end

    it 'excludes events outside the week period' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        # Event from 2 weeks ago (should not be counted)
        create(:event, account: account, project: project, issue: issue,
               occurred_at: Time.zone.local(2025, 1, 6, 12, 0, 0))

        # Event from current week (should not be counted)
        create(:event, account: account, project: project, issue: issue,
               occurred_at: Time.zone.local(2025, 1, 20, 8, 0, 0))

        # Event from previous week (should be counted)
        create(:event, account: account, project: project, issue: issue,
               occurred_at: Time.zone.local(2025, 1, 15, 12, 0, 0))

        builder = described_class.new(account)
        report = builder.build

        expect(report[:total_errors]).to eq(1)
      end
    end
  end

  describe '#performance_by_day' do
    it 'returns all 7 days of the week even with no events' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        builder = described_class.new(account)
        report = builder.build

        expect(report[:performance_by_day].keys.count).to eq(7)
        expect(report[:performance_by_day].values).to all(eq(0))
      end
    end

    it 'counts performance events correctly per day' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        # Monday Jan 13: 2 performance events
        2.times do
          create(:performance_event, account: account, project: project,
                 occurred_at: Time.zone.local(2025, 1, 13, 12, 0, 0))
        end

        # Friday Jan 17: 4 performance events
        4.times do
          create(:performance_event, account: account, project: project,
                 occurred_at: Time.zone.local(2025, 1, 17, 14, 0, 0))
        end

        builder = described_class.new(account)
        report = builder.build

        perf_by_day = report[:performance_by_day]

        expect(perf_by_day[Date.new(2025, 1, 13)]).to eq(2) # Monday
        expect(perf_by_day[Date.new(2025, 1, 14)]).to eq(0) # Tuesday
        expect(perf_by_day[Date.new(2025, 1, 15)]).to eq(0) # Wednesday
        expect(perf_by_day[Date.new(2025, 1, 16)]).to eq(0) # Thursday
        expect(perf_by_day[Date.new(2025, 1, 17)]).to eq(4) # Friday
        expect(perf_by_day[Date.new(2025, 1, 18)]).to eq(0) # Saturday
        expect(perf_by_day[Date.new(2025, 1, 19)]).to eq(0) # Sunday
      end
    end
  end

  describe '#total_errors_count' do
    it 'counts total events in the period' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        5.times do |i|
          create(:event, account: account, project: project, issue: issue,
                 occurred_at: Time.zone.local(2025, 1, 13 + i, 12, 0, 0))
        end

        builder = described_class.new(account)
        report = builder.build

        expect(report[:total_errors]).to eq(5)
      end
    end
  end

  describe '#total_performance_count' do
    it 'counts total performance events in the period' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        3.times do |i|
          create(:performance_event, account: account, project: project,
                 occurred_at: Time.zone.local(2025, 1, 14 + i, 12, 0, 0))
        end

        builder = described_class.new(account)
        report = builder.build

        expect(report[:total_performance]).to eq(3)
      end
    end
  end

  describe '#top_errors' do
    it 'returns top 5 issues by occurrence count' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        issues = 6.times.map do |i|
          create(:issue, account: account, project: project,
                 exception_class: "Error#{i}")
        end

        # Create varying number of events for each issue
        issues.each_with_index do |iss, index|
          (index + 1).times do
            create(:event, account: account, project: project, issue: iss,
                   exception_class: iss.exception_class,
                   occurred_at: Time.zone.local(2025, 1, 15, 12, 0, 0))
          end
        end

        builder = described_class.new(account)
        report = builder.build

        # Should return top 5, ordered by occurrence count descending
        expect(report[:errors].count).to eq(5)
        expect(report[:errors].first.occurrences).to eq(6)
        expect(report[:errors].last.occurrences).to eq(2)
      end
    end

    it 'includes last_seen timestamp' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        create(:event, account: account, project: project, issue: issue,
               occurred_at: Time.zone.local(2025, 1, 15, 10, 0, 0))
        create(:event, account: account, project: project, issue: issue,
               occurred_at: Time.zone.local(2025, 1, 17, 14, 30, 0))

        builder = described_class.new(account)
        report = builder.build

        expect(report[:errors].first.last_seen).to eq(Time.zone.local(2025, 1, 17, 14, 30, 0))
      end
    end
  end

  describe '#slow_endpoints' do
    it 'returns top 5 slowest endpoints by average duration' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        # Create performance events for different endpoints
        targets = %w[UsersController#index UsersController#show PostsController#index
                     PostsController#create CommentsController#index AdminController#dashboard]

        targets.each_with_index do |target, index|
          3.times do
            create(:performance_event, account: account, project: project,
                   target: target,
                   duration_ms: (index + 1) * 100, # 100ms, 200ms, 300ms, etc.
                   occurred_at: Time.zone.local(2025, 1, 15, 12, 0, 0))
          end
        end

        builder = described_class.new(account)
        report = builder.build

        # Should return top 5, ordered by avg_ms descending
        expect(report[:performance].count).to eq(5)
        expect(report[:performance].first.avg_ms.to_i).to eq(600) # AdminController#dashboard
        expect(report[:performance].first.target).to eq('AdminController#dashboard')
      end
    end

    it 'calculates correct request count and max duration' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        create(:performance_event, account: account, project: project,
               target: 'TestController#action', duration_ms: 100,
               occurred_at: Time.zone.local(2025, 1, 15, 12, 0, 0))
        create(:performance_event, account: account, project: project,
               target: 'TestController#action', duration_ms: 300,
               occurred_at: Time.zone.local(2025, 1, 15, 13, 0, 0))
        create(:performance_event, account: account, project: project,
               target: 'TestController#action', duration_ms: 200,
               occurred_at: Time.zone.local(2025, 1, 15, 14, 0, 0))

        builder = described_class.new(account)
        report = builder.build

        endpoint = report[:performance].first
        expect(endpoint.requests).to eq(3)
        expect(endpoint.avg_ms.to_i).to eq(200) # (100 + 300 + 200) / 3
        expect(endpoint.max_ms.to_i).to eq(300)
      end
    end
  end

  describe 'tenant isolation' do
    it 'only includes events from the specified account' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        other_account = create(:account)
        other_project = create(:project, account: other_account)
        other_issue = create(:issue, account: other_account, project: other_project)

        # Events for our account
        2.times do
          create(:event, account: account, project: project, issue: issue,
                 occurred_at: Time.zone.local(2025, 1, 15, 12, 0, 0))
        end

        # Events for other account (should not be counted)
        ActsAsTenant.with_tenant(other_account) do
          3.times do
            create(:event, account: other_account, project: other_project, issue: other_issue,
                   occurred_at: Time.zone.local(2025, 1, 15, 12, 0, 0))
          end
        end

        builder = described_class.new(account)
        report = builder.build

        expect(report[:total_errors]).to eq(2)
      end
    end
  end

  describe 'edge cases' do
    it 'handles events at exact boundary times' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        # Event at very start of period (Monday 00:00:00)
        create(:event, account: account, project: project, issue: issue,
               occurred_at: Time.zone.local(2025, 1, 13, 0, 0, 0))

        # Event at very end of period (Sunday 23:59:59)
        create(:event, account: account, project: project, issue: issue,
               occurred_at: Time.zone.local(2025, 1, 19, 23, 59, 59))

        # Event just before period (Sunday 23:59:59 of week before)
        create(:event, account: account, project: project, issue: issue,
               occurred_at: Time.zone.local(2025, 1, 12, 23, 59, 59))

        # Event just after period (Monday 00:00:00 of current week)
        create(:event, account: account, project: project, issue: issue,
               occurred_at: Time.zone.local(2025, 1, 20, 0, 0, 0))

        builder = described_class.new(account)
        report = builder.build

        # Only the 2 events within the period should be counted
        expect(report[:total_errors]).to eq(2)
      end
    end

    it 'handles empty account with no data' do
      travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
        builder = described_class.new(account)
        report = builder.build

        expect(report[:errors]).to be_empty
        expect(report[:performance]).to be_empty
        expect(report[:total_errors]).to eq(0)
        expect(report[:total_performance]).to eq(0)
        expect(report[:errors_by_day].values.sum).to eq(0)
        expect(report[:performance_by_day].values.sum).to eq(0)
      end
    end
  end
end
