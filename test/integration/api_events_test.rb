require "test_helper"

class ApiEventsTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @token = api_tokens(:default)
    @headers = { "CONTENT_TYPE" => "application/json", "X-Project-Token" => @token.token }
  end

  # POST /api/v1/events/errors

  test "POST /api/v1/events/errors queues error event when valid" do
    body = {
      exception_class: "RuntimeError",
      message: "Boom",
      backtrace: ["/app/controllers/home_controller.rb:10:in `index'"],
      occurred_at: Time.current.iso8601
    }.to_json

    post "/api/v1/events/errors", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal "created", json["status"]
  end

  test "POST /api/v1/events/errors accepts structured_stack_trace with source context" do
    structured_frames = [
      {
        file: "app/controllers/users_controller.rb",
        line: 25,
        method: "show",
        raw: "app/controllers/users_controller.rb:25:in `show'",
        in_app: true,
        frame_type: "controller",
        index: 0,
        source_context: {
          lines_before: ["  def show", "    @user = User.find(params[:id])"],
          line_content: "    raise 'Not found'",
          lines_after: ["  end"],
          start_line: 23
        }
      }
    ]

    body = {
      exception_class: "ArgumentError",
      message: "User not found",
      backtrace: structured_frames.map { |f| f[:raw] },
      structured_stack_trace: structured_frames,
      culprit_frame: structured_frames.first,
      occurred_at: Time.current.iso8601
    }.to_json

    post "/api/v1/events/errors", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal "created", json["status"]
  end

  test "POST /api/v1/events/errors works without structured_stack_trace (backward compatibility)" do
    body = {
      exception_class: "StandardError",
      message: "Legacy error",
      backtrace: ["app/models/user.rb:10:in `save'"],
      occurred_at: Time.current.iso8601
    }.to_json

    post "/api/v1/events/errors", params: body, headers: @headers

    assert_response :created
  end

  test "POST /api/v1/events/errors rejects missing fields" do
    body = { message: "no class" }.to_json

    post "/api/v1/events/errors", params: body, headers: @headers

    assert_response :unprocessable_entity
  end

  # POST /api/v1/events/performance

  test "POST /api/v1/events/performance queues performance event when valid" do
    body = {
      controller_action: "HomeController#index",
      duration_ms: 250.2,
      occurred_at: Time.current.iso8601
    }.to_json

    post "/api/v1/events/performance", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal "created", json["status"]
  end

  test "POST /api/v1/events/performance rejects missing duration" do
    body = { controller_action: "HomeController#index" }.to_json

    post "/api/v1/events/performance", params: body, headers: @headers

    assert_response :unprocessable_entity
  end

  test "POST /api/v1/events/performance accepts controller/action details from metadata" do
    body = {
      name: "controller.action",
      duration_ms: 87.5,
      metadata: {
        controller: "HomeController",
        action: "index",
        method: "GET",
        path: "/home",
        db_runtime: 12.3,
        view_runtime: 4.2
      }
    }.to_json

    post "/api/v1/events/performance", params: body, headers: @headers

    assert_response :created
  end

  # POST /api/v1/events/batch

  test "POST /api/v1/events/batch accepts mixed events and returns processed_count" do
    body = {
      events: [
        { event_type: "error", data: { exception_class: "RuntimeError", message: "x" } },
        { event_type: "performance", data: { controller_action: "HomeController#index", duration_ms: 120.0 } }
      ]
    }.to_json

    post "/api/v1/events/batch", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 2, json["data"]["processed_count"]
  end

  test "POST /api/v1/events/batch rejects empty payload" do
    post "/api/v1/events/batch", params: { events: [] }.to_json, headers: @headers

    assert_response :unprocessable_entity
  end

  test "POST /api/v1/events/batch infers performance type from slow_query name when type is nil" do
    body = {
      events: [
        {
          type: nil,
          data: {
            name: "slow_query",
            properties: { sql: "SELECT 1", duration_ms: 150.3, name: "test" },
            timestamp: Time.current.iso8601,
            environment: "production",
            server_name: "test-server",
            context: { runtime: { name: "ruby", version: "3.4.8" } }
          }
        }
      ]
    }.to_json

    post "/api/v1/events/batch", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 1, json["data"]["processed_count"], "slow_query with type:nil should be inferred as performance"
  end

  test "POST /api/v1/events/batch infers performance type from sidekiq_job_completed name" do
    body = {
      events: [
        {
          type: nil,
          data: {
            name: "sidekiq_job_completed",
            properties: { worker_class: "MyJob", queue: "default", duration_ms: 500.0 },
            timestamp: Time.current.iso8601,
            environment: "production"
          }
        }
      ]
    }.to_json

    post "/api/v1/events/batch", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 1, json["data"]["processed_count"]
  end

  test "POST /api/v1/events/batch infers performance type from slow_template_render name" do
    body = {
      events: [
        {
          type: nil,
          data: {
            name: "slow_template_render",
            properties: { template: "users/show.html.erb", duration_ms: 200.0 },
            timestamp: Time.current.iso8601,
            environment: "production"
          }
        }
      ]
    }.to_json

    post "/api/v1/events/batch", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 1, json["data"]["processed_count"]
  end

  test "POST /api/v1/events/batch handles mixed nil-type and explicit-type events" do
    body = {
      events: [
        { event_type: "error", data: { exception_class: "RuntimeError", message: "boom" } },
        { type: nil, data: { name: "slow_query", properties: { sql: "SELECT 1", duration_ms: 100.0 }, timestamp: Time.current.iso8601, environment: "production" } },
        { event_type: "performance", data: { controller_action: "UsersController#index", duration_ms: 50.0 } }
      ]
    }.to_json

    post "/api/v1/events/batch", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 3, json["data"]["processed_count"], "All 3 events should be processed"
    assert_equal 3, json["data"]["total_count"]
  end

  test "POST /api/v1/events/batch accepts up to 500 events" do
    body = {
      events: [
        { event_type: "error", data: { exception_class: "RuntimeError", message: "test" } }
      ] * 500
    }.to_json

    post "/api/v1/events/batch", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 500, json["data"]["total_count"]
  end

  test "POST /api/v1/events/batch rejects more than 500 events" do
    body = {
      events: [
        { event_type: "error", data: { exception_class: "RuntimeError", message: "test" } }
      ] * 501
    }.to_json

    post "/api/v1/events/batch", params: body, headers: @headers

    assert_response :unprocessable_entity
  end

  test "POST /api/v1/events/batch skips events with completely unknown type" do
    body = {
      events: [
        { type: nil, data: { name: "some_unknown_metric", properties: { value: 42 } } }
      ]
    }.to_json

    post "/api/v1/events/batch", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 0, json["data"]["processed_count"], "Unknown event type should be skipped"
  end

  test "POST /api/v1/events/batch reads type field from top level" do
    body = {
      events: [
        { type: "error", data: { exception_class: "RuntimeError", message: "from type field" } }
      ]
    }.to_json

    post "/api/v1/events/batch", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 1, json["data"]["processed_count"]
  end

  # Self-monitoring filter

  test "POST /api/v1/events/batch filters out self-monitoring API events" do
    body = {
      events: [
        {
          type: "performance",
          data: {
            name: "controller.action",
            controller_action: "Api::V1::EventsController#create_batch",
            request_path: "/api/v1/events/batch",
            request_method: "POST",
            duration_ms: 750.0,
            timestamp: Time.current.iso8601,
            environment: "production"
          }
        },
        {
          type: "performance",
          data: {
            name: "controller.action",
            controller_action: "HomeController#index",
            request_path: "/home",
            request_method: "GET",
            duration_ms: 50.0,
            timestamp: Time.current.iso8601,
            environment: "production"
          }
        }
      ]
    }.to_json

    post "/api/v1/events/batch", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 1, json["data"]["processed_count"], "Self-monitoring API events should be filtered out"
    assert_equal 2, json["data"]["total_count"]
  end

  test "POST /api/v1/events/batch filters out events by API request_path" do
    body = {
      events: [
        {
          type: "performance",
          data: {
            name: "controller.action",
            controller_action: "Api::V1::EventsController#create_error",
            request_path: "/api/v1/events/errors",
            request_method: "POST",
            duration_ms: 100.0,
            timestamp: Time.current.iso8601,
            environment: "production"
          }
        }
      ]
    }.to_json

    post "/api/v1/events/batch", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 0, json["data"]["processed_count"], "Events about API endpoints should be filtered"
  end

  # POST /api/v1/test/connection

  test "POST /api/v1/test/connection returns project context" do
    post "/api/v1/test/connection", headers: @headers

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal @project.id, json["project_id"]
    assert_equal "success", json["status"]
  end

  # Authentication errors

  test "rejects missing token" do
    post "/api/v1/events/errors", params: {}.to_json, headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :unauthorized
  end

  test "rejects invalid token" do
    post "/api/v1/events/errors", params: {}.to_json, headers: { "CONTENT_TYPE" => "application/json", "X-Project-Token" => "bad" }

    assert_response :unauthorized
  end
end
