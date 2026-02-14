require "test_helper"

class DataRetentionJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @issue = issues(:open_issue)
  end

  # ===========================================================================
  # Constants
  # ===========================================================================

  test "DEFAULT_RETENTION_DAYS is set to 31" do
    assert_equal 31, DataRetentionJob::DEFAULT_RETENTION_DAYS
  end

  test "FREE_PLAN_RETENTION_DAYS is set to 5" do
    assert_equal 5, DataRetentionJob::FREE_PLAN_RETENTION_DAYS
  end

  # ===========================================================================
  # Global retention (31 days for all accounts)
  # ===========================================================================

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

  # ===========================================================================
  # Free plan retention (5 days)
  # ===========================================================================

  test "deletes free plan events older than 5 days" do
    free_account = accounts(:free_account)
    free_project = projects(:free_project)
    ActsAsTenant.current_tenant = free_account

    # Create an issue for the free project
    issue = Issue.create!(
      project: free_project,
      account: free_account,
      exception_class: "RetentionError",
      fingerprint: SecureRandom.hex(16),
      status: "open",
      count: 1,
      top_frame: "app/models/retention.rb:1:in `check'",
      controller_action: "RetentionController#check",
      first_seen_at: 6.days.ago,
      last_seen_at: 6.days.ago
    )

    old_event = Event.create!(
      account: free_account,
      project: free_project,
      issue: issue,
      exception_class: "RuntimeError",
      message: "Old free plan event",
      occurred_at: 6.days.ago,
      environment: "production"
    )
    recent_event = Event.create!(
      account: free_account,
      project: free_project,
      issue: issue,
      exception_class: "RuntimeError",
      message: "Recent free plan event",
      occurred_at: 4.days.ago,
      environment: "production"
    )

    ActsAsTenant.current_tenant = nil
    DataRetentionJob.new.perform

    refute Event.exists?(old_event.id),
      "Free plan event older than 5 days should be deleted"
    assert Event.exists?(recent_event.id),
      "Free plan event within 5 days should be kept"
  end

  test "deletes free plan performance events older than 5 days" do
    free_account = accounts(:free_account)
    free_project = projects(:free_project)
    ActsAsTenant.current_tenant = free_account

    old_perf = PerformanceEvent.create!(
      account: free_account,
      project: free_project,
      target: "FreeController#index",
      duration_ms: 100,
      occurred_at: 6.days.ago,
      environment: "production"
    )
    recent_perf = PerformanceEvent.create!(
      account: free_account,
      project: free_project,
      target: "FreeController#index",
      duration_ms: 100,
      occurred_at: 4.days.ago,
      environment: "production"
    )

    ActsAsTenant.current_tenant = nil
    DataRetentionJob.new.perform

    refute PerformanceEvent.exists?(old_perf.id),
      "Free plan performance event older than 5 days should be deleted"
    assert PerformanceEvent.exists?(recent_perf.id),
      "Free plan performance event within 5 days should be kept"
  end

  test "does not delete paid plan events older than 5 days but under 31 days" do
    # Default account is on team plan (via trial)
    event = Event.create!(
      account: @account,
      project: @project,
      issue: @issue,
      exception_class: "RuntimeError",
      message: "Paid plan 10-day-old event",
      occurred_at: 10.days.ago,
      environment: "production"
    )

    DataRetentionJob.new.perform

    assert Event.exists?(event.id),
      "Paid plan event from 10 days ago should NOT be deleted (31-day retention)"
  end
end
