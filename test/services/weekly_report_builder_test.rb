require "test_helper"

class WeeklyReportBuilderTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @issue = issues(:open_issue)
  end

  # Period calculation

  test "sets period to previous calendar week Mon-Sun" do
    travel_to Time.zone.local(2025, 1, 15, 10, 0, 0) do
      builder = WeeklyReportBuilder.new(@account)
      report = builder.build

      # Previous week should be Mon Jan 6 to Sun Jan 12
      assert_equal Time.zone.local(2025, 1, 6, 0, 0, 0), report[:period].first
      assert_equal Date.new(2025, 1, 12), report[:period].last.to_date
      assert_equal 23, report[:period].last.hour
      assert_equal 59, report[:period].last.min
    end
  end

  test "covers exactly 7 days Mon through Sun" do
    travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
      builder = WeeklyReportBuilder.new(@account)
      report = builder.build

      period_start = report[:period].first.to_date
      period_end = report[:period].last.to_date

      assert_equal 6, (period_end - period_start)
      assert period_start.monday?
      assert period_end.sunday?
    end
  end

  # errors_by_day

  test "errors_by_day returns all 7 days even with no events" do
    travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
      builder = WeeklyReportBuilder.new(@account)
      report = builder.build

      assert_equal 7, report[:errors_by_day].keys.count
      assert report[:errors_by_day].values.all? { |v| v == 0 }
    end
  end

  test "errors_by_day returns days in order from Monday to Sunday" do
    travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
      builder = WeeklyReportBuilder.new(@account)
      report = builder.build

      days = report[:errors_by_day].keys
      assert_equal "Monday", days[0].strftime("%A")
      assert_equal "Tuesday", days[1].strftime("%A")
      assert_equal "Wednesday", days[2].strftime("%A")
      assert_equal "Thursday", days[3].strftime("%A")
      assert_equal "Friday", days[4].strftime("%A")
      assert_equal "Saturday", days[5].strftime("%A")
      assert_equal "Sunday", days[6].strftime("%A")
    end
  end

  # performance_by_day

  test "performance_by_day returns all 7 days even with no events" do
    travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
      builder = WeeklyReportBuilder.new(@account)
      report = builder.build

      assert_equal 7, report[:performance_by_day].keys.count
      assert report[:performance_by_day].values.all? { |v| v == 0 }
    end
  end

  # Empty account

  test "handles empty account with no data" do
    travel_to Time.zone.local(2025, 1, 20, 9, 0, 0) do
      builder = WeeklyReportBuilder.new(@account)
      report = builder.build

      assert_empty report[:errors]
      assert_empty report[:performance]
      assert_equal 0, report[:total_errors]
      assert_equal 0, report[:total_performance]
      assert_equal 0, report[:errors_by_day].values.sum
      assert_equal 0, report[:performance_by_day].values.sum
    end
  end
end
