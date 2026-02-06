require "test_helper"

class ReportUsageJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
  end

  test "aggregates daily resource usage" do
    aggregation_called = false

    DailyResourceUsage.stub(:aggregate_for_account_and_day, ->(_account_id, _day) {
      aggregation_called = true
    }) do
      UsageReporter.stub(:new, ->(**args) {
        OpenStruct.new(report_daily!: true)
      }) do
        ReportUsageJob.perform_now(account_id: @account.id)
      end
    end

    assert aggregation_called
  end

  test "reports to usage reporter" do
    reporter_called = false

    DailyResourceUsage.stub(:aggregate_for_account_and_day, true) do
      UsageReporter.stub(:new, ->(**args) {
        OpenStruct.new(report_daily!: -> { reporter_called = true; true }.call)
      }) do
        ReportUsageJob.perform_now(account_id: @account.id)
      end
    end

    assert reporter_called
  end

  test "handles account not found gracefully" do
    assert_nothing_raised do
      ReportUsageJob.perform_now(account_id: 999999)
    end
  end

  test "uses specified day parameter" do
    yesterday = Date.current - 1.day
    day_checked = nil

    DailyResourceUsage.stub(:aggregate_for_account_and_day, ->(_account_id, day) {
      day_checked = day
    }) do
      UsageReporter.stub(:new, ->(**args) {
        OpenStruct.new(report_daily!: true)
      }) do
        ReportUsageJob.perform_now(account_id: @account.id, day: yesterday)
      end
    end

    assert_equal yesterday, day_checked
  end

  test "defaults to current date" do
    day_checked = nil

    DailyResourceUsage.stub(:aggregate_for_account_and_day, ->(_account_id, day) {
      day_checked = day
    }) do
      UsageReporter.stub(:new, ->(**args) {
        OpenStruct.new(report_daily!: true)
      }) do
        ReportUsageJob.perform_now(account_id: @account.id)
      end
    end

    assert_equal Date.current, day_checked
  end
end
