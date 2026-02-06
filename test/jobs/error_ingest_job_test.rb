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

    # Stub the AI summary to avoid external calls
    AiSummaryService.stub(:new, ->(*args) {
      mock = Minitest::Mock.new
      mock.expect(:call, { summary: "Test summary" })
      mock
    }) do
      assert_changes -> { Event.count } do
        ErrorIngestJob.new.perform(@project.id, payload)
      end
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

    AiSummaryService.stub(:new, ->(*args) {
      OpenStruct.new(call: { summary: nil })
    }) do
      ErrorIngestJob.new.perform(@project.id, payload)
    end

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

    AiSummaryService.stub(:new, ->(*args) {
      OpenStruct.new(call: { summary: nil })
    }) do
      assert_difference "SqlFingerprint.count", 2 do
        ErrorIngestJob.new.perform(@project.id, payload)
      end
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

    AiSummaryService.stub(:new, ->(*args) {
      OpenStruct.new(call: { summary: nil })
    }) do
      assert_nothing_raised do
        ErrorIngestJob.new.perform(@project.id, payload)
      end
    end
  end
end
