require "test_helper"

class DataRetentionJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @issue = issues(:open_issue)
  end

  test "deletes events older than 31 days" do
    old_event = Event.create!(
      account: @account,
      project: @project,
      issue: @issue,
      exception_class: "RuntimeError",
      message: "Old error",
      occurred_at: 32.days.ago,
      environment: "production"
    )
    recent_event = Event.create!(
      account: @account,
      project: @project,
      issue: @issue,
      exception_class: "RuntimeError",
      message: "Recent error",
      occurred_at: 30.days.ago,
      environment: "production"
    )

    DataRetentionJob.new.perform

    refute Event.exists?(old_event.id)
    assert Event.exists?(recent_event.id)
  end

  test "deletes performance events older than 31 days" do
    old_perf = PerformanceEvent.create!(
      account: @account,
      project: @project,
      target: "Controller#action",
      duration_ms: 100,
      occurred_at: 32.days.ago,
      environment: "production"
    )
    recent_perf = PerformanceEvent.create!(
      account: @account,
      project: @project,
      target: "Controller#action",
      duration_ms: 100,
      occurred_at: 30.days.ago,
      environment: "production"
    )

    DataRetentionJob.new.perform

    refute PerformanceEvent.exists?(old_perf.id)
    assert PerformanceEvent.exists?(recent_perf.id)
  end

  test "completes without errors when tables are empty" do
    assert_nothing_raised do
      DataRetentionJob.new.perform
    end
  end

  test "RETENTION_DAYS is set to 31" do
    assert_equal 31, DataRetentionJob::RETENTION_DAYS
  end
end
