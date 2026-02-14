require "test_helper"

class ErrorIngestJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
    # Clear Redis AI summary counters to prevent cross-test pollution
    Sidekiq.redis { |c| c.del("ai_summary_enqueued:#{@account.id}:#{Date.current.strftime('%Y-%m')}") }
  end

  test "processes error event and creates event record" do
    payload = {
      exception_class: "RuntimeError",
      message: "Test error",
      backtrace: ["app/models/user.rb:10:in `process'"],
      controller_action: "UsersController#create",
      environment: "production"
    }

    assert_changes -> { Event.count } do
      ErrorIngestJob.new.perform(@project.id, payload)
    end
  end

  test "updates project last_event_at" do
    payload = {
      exception_class: "StandardError",
      message: "Test error",
      backtrace: [],
      controller_action: "HomeController#index",
      environment: "production"
    }

    original_time = @project.last_event_at

    ErrorIngestJob.new.perform(@project.id, payload)

    @project.reload
    if original_time.present?
      assert @project.last_event_at >= original_time
    else
      assert @project.last_event_at.present?
    end
  end

  test "raises error when project not found" do
    payload = { exception_class: "RuntimeError", message: "Test" }

    assert_raises ActiveRecord::RecordNotFound do
      ErrorIngestJob.new.perform(999999, payload)
    end
  end

  test "tracks SQL queries when provided" do
    payload = {
      exception_class: "RuntimeError",
      message: "Test error",
      backtrace: [],
      controller_action: "UsersController#index",
      environment: "production",
      sql_queries: [
        { sql: "SELECT * FROM users WHERE id = 1", duration_ms: 5 },
        { sql: "SELECT * FROM posts WHERE user_id = 1", duration_ms: 10 }
      ]
    }

    assert_difference "SqlFingerprint.count", 2 do
      ErrorIngestJob.new.perform(@project.id, payload)
    end
  end

  test "handles payload with string keys" do
    payload = {
      "exception_class" => "RuntimeError",
      "message" => "String key test",
      "backtrace" => [],
      "controller_action" => "HomeController#show",
      "environment" => "production"
    }

    assert_nothing_raised do
      ErrorIngestJob.new.perform(@project.id, payload)
    end
  end

  # Alert triggering logic

  test "should_alert_for_issue returns true for new issue (count=1)" do
    job = ErrorIngestJob.new
    issue = issues(:open_issue)
    issue.update!(count: 1, status: "open", closed_at: nil)
    assert job.send(:should_alert_for_issue?, issue)
  end

  test "should_alert_for_issue returns true for recently closed recurring issue" do
    job = ErrorIngestJob.new
    issue = issues(:open_issue)
    issue.update!(count: 5, status: "open", closed_at: 6.hours.ago)
    assert job.send(:should_alert_for_issue?, issue)
  end

  test "should_alert_for_issue returns false for closed status" do
    job = ErrorIngestJob.new
    issue = issues(:closed_issue)
    refute job.send(:should_alert_for_issue?, issue)
  end

  test "should_alert_for_issue returns false for low frequency existing issue" do
    job = ErrorIngestJob.new
    issue = issues(:open_issue)
    issue.update!(count: 5, status: "open", closed_at: nil)
    # No recent events in last hour = low frequency
    refute job.send(:should_alert_for_issue?, issue)
  end

  test "triggers IssueAlertJob for new issues" do
    payload = {
      exception_class: "NewFatalError",
      message: "Brand new error",
      backtrace: ["app/controllers/new_controller.rb:1:in `create'"],
      controller_action: "NewController#create",
      environment: "production"
    }

    ErrorIngestJob.new.perform(@project.id, payload)

    # Verify the issue was created with count 1
    issue = Issue.find_by(exception_class: "NewFatalError")
    assert issue.present?
    assert_equal 1, issue.count
  end

  # ============================================================================
  # Auto AI Summary enqueue tests
  # ============================================================================

  test "auto-enqueues AiSummaryJob for new issue when account is eligible" do
    Sidekiq::Worker.clear_all

    payload = {
      exception_class: "BrandNewAutoAIError",
      message: "AI summary should be auto-generated for new issues",
      backtrace: ["app/models/foo.rb:1:in `bar'"],
      controller_action: "FooController#bar",
      environment: "production"
    }

    # Default account is on trial (trial_ends_at = 7.days.from_now),
    # trial plan gets 20 AI summaries, 0 used → eligible
    ErrorIngestJob.new.perform(@project.id, payload)

    assert_equal 1, AiSummaryJob.jobs.size,
      "AiSummaryJob should be auto-enqueued for new issues within quota"
  end

  test "does not auto-enqueue AiSummaryJob for duplicate issue (count > 1)" do
    # First create the issue
    payload = {
      exception_class: "DuplicateAutoAIError",
      message: "Should only auto-generate on first occurrence",
      backtrace: ["app/models/dup.rb:1:in `run'"],
      controller_action: "DupController#run",
      environment: "production",
      request_id: SecureRandom.uuid
    }

    ErrorIngestJob.new.perform(@project.id, payload)
    Sidekiq::Worker.clear_all

    # Second occurrence of same error — different request_id since
    # it's a genuinely separate event (not a Sidekiq double-fire)
    payload[:request_id] = SecureRandom.uuid
    ErrorIngestJob.new.perform(@project.id, payload)

    assert_equal 0, AiSummaryJob.jobs.size,
      "AiSummaryJob should not be auto-enqueued for duplicate issues (count > 1)"
  end

  test "does not auto-enqueue AiSummaryJob when AI quota is exceeded" do
    Sidekiq::Worker.clear_all

    # Exhaust the trial quota (20)
    @account.update!(cached_ai_summaries_used: 20)

    payload = {
      exception_class: "QuotaExceededAutoAIError",
      message: "Over quota",
      backtrace: ["app/models/quota.rb:1:in `check'"],
      controller_action: "QuotaController#check",
      environment: "production"
    }

    ErrorIngestJob.new.perform(@project.id, payload)

    assert_equal 0, AiSummaryJob.jobs.size,
      "AiSummaryJob should not be auto-enqueued when AI quota is exceeded"
  end

  test "does not auto-enqueue AiSummaryJob for team plan without active subscription" do
    Sidekiq::Worker.clear_all

    # Make the default account look like a team plan with expired trial and no subscription
    @account.update!(current_plan: "team", trial_ends_at: nil, cached_ai_summaries_used: 0)

    payload = {
      exception_class: "TeamNoSubAutoAIError",
      message: "Team plan without subscription should not auto-generate",
      backtrace: ["app/models/team.rb:1:in `work'"],
      controller_action: "TeamController#work",
      environment: "production"
    }

    ErrorIngestJob.new.perform(@project.id, payload)

    assert_equal 0, AiSummaryJob.jobs.size,
      "AiSummaryJob should not be auto-enqueued for team plan without active subscription"
  end

  # ============================================================================
  # Idempotency / deduplication tests
  # ============================================================================

  test "skips duplicate processing when same payload is performed twice" do
    # Use SecureRandom to avoid collisions with parallel test processes
    dedup_request_id = SecureRandom.uuid
    payload = {
      exception_class: "DedupTestError",
      message: "Should only be ingested once",
      backtrace: ["app/models/dedup.rb:1:in `run'"],
      controller_action: "DedupController#run",
      environment: "production",
      request_id: dedup_request_id
    }

    # First call creates the event
    assert_difference "Event.count", 1 do
      ErrorIngestJob.new.perform(@project.id, payload)
    end

    # Second call with same payload is deduplicated — no new event
    assert_no_difference "Event.count" do
      ErrorIngestJob.new.perform(@project.id, payload)
    end
  ensure
    Sidekiq.redis { |c| c.del("ingest_dedup:#{@project.id}:#{dedup_request_id}") }
  end

  test "processes events with different request_ids independently" do
    req1 = SecureRandom.uuid
    req2 = SecureRandom.uuid
    base_payload = {
      exception_class: "IndependentTestError",
      message: "Same error, different requests",
      backtrace: ["app/models/ind.rb:1:in `run'"],
      controller_action: "IndController#run",
      environment: "production"
    }

    assert_difference "Event.count", 2 do
      ErrorIngestJob.new.perform(@project.id, base_payload.merge(request_id: req1))
      ErrorIngestJob.new.perform(@project.id, base_payload.merge(request_id: req2))
    end

    # Issue count should be 2 (atomic increment for both events)
    issue = Issue.find_by(exception_class: "IndependentTestError")
    assert_equal 2, issue.count
  ensure
    Sidekiq.redis do |c|
      c.del("ingest_dedup:#{@project.id}:#{req1}")
      c.del("ingest_dedup:#{@project.id}:#{req2}")
    end
  end

  test "does NOT auto-enqueue AiSummaryJob for free plan (0 AI quota)" do
    Sidekiq::Worker.clear_all
    # Clear Redis counter again right before this test (parallel workers may pollute)
    Sidekiq.redis { |c| c.del("ai_summary_enqueued:#{@account.id}:#{Date.current.strftime('%Y-%m')}") }

    # Make the default account look like a free plan with expired trial
    @account.update!(current_plan: "free", trial_ends_at: 1.day.ago, cached_ai_summaries_used: 0)

    payload = {
      exception_class: "FreeAutoAIError",
      message: "Free plan has 0 AI summaries — should not enqueue",
      backtrace: ["app/models/free.rb:1:in `go'"],
      controller_action: "FreeController#go",
      environment: "production"
    }

    ErrorIngestJob.new.perform(@project.id, payload)

    assert_equal 0, AiSummaryJob.jobs.size,
      "AiSummaryJob should NOT be auto-enqueued for free plan (0 AI quota)"
  end

  # ============================================================================
  # Free plan hard cap safety net
  # ============================================================================

  test "drops event when free plan event cap is reached" do
    free_account = accounts(:free_account)
    free_project = projects(:free_project)
    ActsAsTenant.current_tenant = free_account

    # Exhaust the free plan quota
    free_account.update!(cached_events_used: 5_001)

    payload = {
      exception_class: "CappedError",
      message: "Should be dropped by safety net",
      backtrace: ["app/models/capped.rb:1:in `run'"],
      controller_action: "CappedController#run",
      environment: "production"
    }

    assert_no_difference "Event.count" do
      ErrorIngestJob.new.perform(free_project.id, payload)
    end
  end

  test "processes event when free plan is under cap" do
    free_account = accounts(:free_account)
    free_project = projects(:free_project)
    ActsAsTenant.current_tenant = free_account

    free_account.update!(cached_events_used: 100)

    payload = {
      exception_class: "UnderCapError",
      message: "Should be processed normally",
      backtrace: ["app/models/under.rb:1:in `run'"],
      controller_action: "UnderController#run",
      environment: "production"
    }

    assert_difference "Event.count", 1 do
      ErrorIngestJob.new.perform(free_project.id, payload)
    end
  end

  test "does not drop events for team plan even when over quota" do
    # Default account is on team plan (trial) — no hard cap
    @account.update!(cached_events_used: 999_999)

    payload = {
      exception_class: "TeamOverQuotaError",
      message: "Team plan uses overage billing, not hard cap",
      backtrace: ["app/models/team.rb:1:in `run'"],
      controller_action: "TeamController#run",
      environment: "production"
    }

    assert_difference "Event.count", 1 do
      ErrorIngestJob.new.perform(@project.id, payload)
    end
  end
end
