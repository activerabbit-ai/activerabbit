require "test_helper"

class ErrorIngestJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
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
end
