require "test_helper"

class UsageSnapshotJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @issue = issues(:open_issue)
    @account.update!(
      event_usage_period_start: Time.current.beginning_of_month,
      event_usage_period_end: Time.current.end_of_month
    )
  end

  test "counts events in billing period" do
    Event.create!(
      account: @account,
      project: @project,
      issue: @issue,
      exception_class: "RuntimeError",
      message: "Error",
      occurred_at: Time.current,
      environment: "production"
    )
    Event.create!(
      account: @account,
      project: @project,
      issue: @issue,
      exception_class: "RuntimeError",
      message: "Error 2",
      occurred_at: 1.day.ago,
      environment: "production"
    )

    UsageSnapshotJob.new.perform

    @account.reload
    assert @account.cached_events_used >= 2
  end

  test "updates usage_cached_at timestamp" do
    @account.update!(usage_cached_at: nil)

    UsageSnapshotJob.new.perform

    @account.reload
    assert @account.usage_cached_at.present?
    assert_in_delta Time.current, @account.usage_cached_at, 1.minute
  end

  test "counts performance events in billing period" do
    PerformanceEvent.create!(
      account: @account,
      project: @project,
      target: "Controller#action",
      duration_ms: 100,
      occurred_at: Time.current,
      environment: "production"
    )

    UsageSnapshotJob.new.perform

    @account.reload
    assert @account.cached_performance_events_used >= 1
  end

  test "sets cached values to 0 with no data" do
    # Use an account with no associated data (trial_account has no events/projects)
    empty_account = accounts(:trial_account)
    empty_account.update!(
      event_usage_period_start: Time.current.beginning_of_month,
      event_usage_period_end: Time.current.end_of_month
    )

    UsageSnapshotJob.new.perform

    empty_account.reload
    assert_equal 0, empty_account.cached_events_used
    assert_equal 0, empty_account.cached_performance_events_used
    assert_equal 0, empty_account.cached_ai_summaries_used
    assert_equal 0, empty_account.cached_pull_requests_used
    assert_equal 0, empty_account.cached_uptime_monitors_used
    assert_equal 0, empty_account.cached_status_pages_used
  end

  test "defaults to current month when billing period not set" do
    @account.update!(
      event_usage_period_start: nil,
      event_usage_period_end: nil
    )

    Event.create!(
      account: @account,
      project: @project,
      issue: @issue,
      exception_class: "RuntimeError",
      message: "Error",
      occurred_at: Time.current,
      environment: "production"
    )

    UsageSnapshotJob.new.perform

    @account.reload
    assert @account.cached_events_used >= 1
  end
end
