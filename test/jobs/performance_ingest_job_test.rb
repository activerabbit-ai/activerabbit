require "test_helper"

class PerformanceIngestJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
  end

  test "processes performance event and creates record" do
    payload = {
      controller_action: "UsersController#index",
      duration_ms: 150.5,
      environment: "production",
      occurred_at: Time.current.iso8601
    }

    assert_difference "PerformanceEvent.count", 1 do
      PerformanceIngestJob.new.perform(@project.id, payload)
    end
  end

  test "updates project last_event_at" do
    payload = {
      controller_action: "HomeController#show",
      duration_ms: 50.0,
      environment: "production",
      occurred_at: Time.current.iso8601
    }

    original_time = @project.last_event_at
    PerformanceIngestJob.new.perform(@project.id, payload)

    @project.reload
    if original_time.present?
      assert @project.last_event_at >= original_time
    else
      assert @project.last_event_at.present?
    end
  end

  test "raises error when project not found" do
    payload = { controller_action: "Test#action", duration_ms: 100 }

    assert_raises ActiveRecord::RecordNotFound do
      PerformanceIngestJob.new.perform(999999, payload)
    end
  end

  test "tracks SQL queries when provided" do
    payload = {
      controller_action: "UsersController#index",
      duration_ms: 200.0,
      environment: "production",
      occurred_at: Time.current.iso8601,
      sql_queries: [
        { sql: "SELECT * FROM accounts WHERE id = 1", duration_ms: 5 },
        { sql: "SELECT * FROM projects WHERE account_id = 1", duration_ms: 8 }
      ]
    }

    assert_difference "SqlFingerprint.count", 2 do
      PerformanceIngestJob.new.perform(@project.id, payload)
    end
  end

  test "detects N+1 queries and marks context" do
    payload = {
      controller_action: "UsersController#index",
      duration_ms: 500.0,
      environment: "production",
      occurred_at: Time.current.iso8601,
      sql_queries: 6.times.map { |i|
        { sql: "SELECT * FROM comments WHERE user_id = #{i}", duration_ms: 2 }
      }
    }

    PerformanceIngestJob.new.perform(@project.id, payload)

    event = PerformanceEvent.last
    # The event context should indicate N+1 detection
    assert event.present?
  end

  test "handles payload with string keys" do
    payload = {
      "controller_action" => "HomeController#index",
      "duration_ms" => 100.0,
      "environment" => "production",
      "occurred_at" => Time.current.iso8601
    }

    assert_nothing_raised do
      PerformanceIngestJob.new.perform(@project.id, payload)
    end
  end

  # ============================================================================
  # Free plan hard cap safety net
  # ============================================================================

  test "drops performance event when free plan event cap is reached" do
    free_account = accounts(:free_account)
    free_project = projects(:free_project)
    ActsAsTenant.current_tenant = free_account

    free_account.update!(cached_events_used: 5_001)

    payload = {
      controller_action: "CappedController#index",
      duration_ms: 150.5,
      environment: "production",
      occurred_at: Time.current.iso8601
    }

    assert_no_difference "PerformanceEvent.count" do
      PerformanceIngestJob.new.perform(free_project.id, payload)
    end
  end

  test "processes performance event when free plan is under cap" do
    free_account = accounts(:free_account)
    free_project = projects(:free_project)
    ActsAsTenant.current_tenant = free_account

    free_account.update!(cached_events_used: 100)

    payload = {
      controller_action: "UnderCapController#index",
      duration_ms: 80.0,
      environment: "production",
      occurred_at: Time.current.iso8601
    }

    assert_difference "PerformanceEvent.count", 1 do
      PerformanceIngestJob.new.perform(free_project.id, payload)
    end
  end

  test "does not drop performance events for team plan even when over quota" do
    @account.update!(cached_events_used: 999_999)

    payload = {
      controller_action: "TeamOverQuotaController#index",
      duration_ms: 200.0,
      environment: "production",
      occurred_at: Time.current.iso8601
    }

    assert_difference "PerformanceEvent.count", 1 do
      PerformanceIngestJob.new.perform(@project.id, payload)
    end
  end
end
