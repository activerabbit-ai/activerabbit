require "test_helper"

class ApiCliTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @token = api_tokens(:default)
    @headers = { "CONTENT_TYPE" => "application/json", "X-Project-Token" => @token.token }

    # Ensure we have some test data
    @open_issue = issues(:open_issue)
    @wip_issue = issues(:wip_issue)
  end

  # =============================================================================
  # Authentication
  # =============================================================================

  test "CLI endpoints require X-Project-Token header" do
    get "/api/v1/cli/apps"
    assert_response :unauthorized

    json = JSON.parse(response.body)
    assert_equal "unauthorized", json["error"]
  end

  test "CLI endpoints reject invalid token" do
    bad_headers = { "CONTENT_TYPE" => "application/json", "X-Project-Token" => "invalid" }

    get "/api/v1/cli/apps", headers: bad_headers
    assert_response :unauthorized
  end

  # =============================================================================
  # GET /api/v1/cli/apps
  # =============================================================================

  test "GET /api/v1/cli/apps returns list of apps" do
    get "/api/v1/cli/apps", headers: @headers

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "apps", json["command"]
    assert json["generated_at"].present?
    assert json["data"]["apps"].is_a?(Array)
  end

  test "GET /api/v1/cli/apps returns app details" do
    get "/api/v1/cli/apps", headers: @headers

    json = JSON.parse(response.body)
    apps = json["data"]["apps"]

    # Should include our default project
    app = apps.find { |a| a["slug"] == @project.slug }
    assert app.present?, "Expected to find project #{@project.slug}"
    assert_equal @project.name, app["name"]
    assert_equal @project.environment, app["environment"]
    assert app.key?("error_count_24h")
  end

  # =============================================================================
  # GET /api/v1/cli/apps/:slug/status
  # =============================================================================

  test "GET /api/v1/cli/apps/:slug/status returns health snapshot" do
    get "/api/v1/cli/apps/#{@project.slug}/status", headers: @headers

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "status", json["command"]
    assert_equal @project.slug, json["project"]

    data = json["data"]
    assert_equal @project.slug, data["app"]
    assert_equal @project.name, data["name"]
    assert data.key?("health")
    assert data.key?("error_count_24h")
    assert data.key?("p95_latency_ms")
    assert data.key?("deploy_status")
  end

  test "GET /api/v1/cli/apps/:slug/status includes top issue" do
    get "/api/v1/cli/apps/#{@project.slug}/status", headers: @headers

    json = JSON.parse(response.body)
    data = json["data"]

    # Should have top_issue if there are open issues
    if @project.issues.open.any?
      assert data["top_issue"].present?
      assert data["top_issue"]["id"].start_with?("inc_")
      assert data["top_issue"]["title"].present?
      assert data["top_issue"]["severity"].present?
    end
  end

  test "GET /api/v1/cli/apps/:slug/status returns 404 for unknown app" do
    get "/api/v1/cli/apps/nonexistent-app/status", headers: @headers

    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal "not_found", json["error"]
  end

  # =============================================================================
  # GET /api/v1/cli/apps/:slug/deploy_check
  # =============================================================================

  test "GET /api/v1/cli/apps/:slug/deploy_check returns deploy safety info" do
    get "/api/v1/cli/apps/#{@project.slug}/deploy_check", headers: @headers

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "deploy_check", json["command"]

    data = json["data"]
    assert [true, false].include?(data["ready"])
    assert data.key?("new_errors_since_deploy")
    assert data["warnings"].is_a?(Array)
  end

  # =============================================================================
  # GET /api/v1/cli/apps/:slug/incidents
  # =============================================================================

  test "GET /api/v1/cli/apps/:slug/incidents returns list of incidents" do
    get "/api/v1/cli/apps/#{@project.slug}/incidents", headers: @headers

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "incidents", json["command"]
    assert json["data"]["incidents"].is_a?(Array)
  end

  test "GET /api/v1/cli/apps/:slug/incidents returns incident details" do
    get "/api/v1/cli/apps/#{@project.slug}/incidents", headers: @headers

    json = JSON.parse(response.body)
    incidents = json["data"]["incidents"]

    # Should have at least our open issue
    assert incidents.any?, "Expected at least one incident"

    incident = incidents.first
    assert incident["id"].start_with?("inc_")
    assert incident["severity"].present?
    assert incident["title"].present?
    assert incident.key?("endpoint")
    assert incident.key?("count")
    assert incident.key?("last_seen_at")
    assert incident.key?("status")
  end

  test "GET /api/v1/cli/apps/:slug/incidents respects limit param" do
    get "/api/v1/cli/apps/#{@project.slug}/incidents?limit=2", headers: @headers

    json = JSON.parse(response.body)
    incidents = json["data"]["incidents"]

    assert incidents.length <= 2
  end

  test "GET /api/v1/cli/apps/:slug/incidents excludes closed issues" do
    get "/api/v1/cli/apps/#{@project.slug}/incidents", headers: @headers

    json = JSON.parse(response.body)
    incidents = json["data"]["incidents"]

    statuses = incidents.map { |i| i["status"] }
    refute_includes statuses, "closed"
  end

  # =============================================================================
  # GET /api/v1/cli/apps/:slug/incidents/:id
  # =============================================================================

  test "GET /api/v1/cli/apps/:slug/incidents/:id returns incident detail" do
    get "/api/v1/cli/apps/#{@project.slug}/incidents/inc_#{@open_issue.id}", headers: @headers

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "incident_detail", json["command"]

    data = json["data"]
    assert_equal "inc_#{@open_issue.id}", data["id"]
    assert_equal @open_issue.exception_class, data["exception_class"]
    assert data.key?("message")
    assert data.key?("backtrace")
    assert data["backtrace"].is_a?(Array)
    assert data.key?("recent_events")
    assert data.key?("affected_users")
  end

  test "GET /api/v1/cli/apps/:slug/incidents/:id accepts id without prefix" do
    get "/api/v1/cli/apps/#{@project.slug}/incidents/#{@open_issue.id}", headers: @headers

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "inc_#{@open_issue.id}", json["data"]["id"]
  end

  test "GET /api/v1/cli/apps/:slug/incidents/:id returns 404 for unknown incident" do
    get "/api/v1/cli/apps/#{@project.slug}/incidents/inc_99999", headers: @headers

    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal "not_found", json["error"]
  end

  # =============================================================================
  # GET /api/v1/cli/apps/:slug/incidents/:id/explain
  # =============================================================================

  test "GET /api/v1/cli/apps/:slug/incidents/:id/explain returns AI analysis with cached summary" do
    # Set up a cached summary to avoid AI calls
    @open_issue.update!(
      ai_summary: "## Root Cause\n\nTest root cause from cache.\n\n## Suggested Fix\n\nTest fix from cache.",
      ai_summary_generated_at: 10.minutes.ago
    )

    get "/api/v1/cli/apps/#{@project.slug}/incidents/inc_#{@open_issue.id}/explain", headers: @headers

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "explain", json["command"]

    data = json["data"]
    assert_equal "inc_#{@open_issue.id}", data["incident_id"]
    assert data.key?("root_cause")
    assert data.key?("suggested_fix")
    assert data.key?("confidence_score")
    assert data["confidence_score"].is_a?(Numeric)
    assert data.key?("regression_risk")
    assert data.key?("tests_to_run")
    assert data["tests_to_run"].is_a?(Array)
  end

  test "GET /api/v1/cli/apps/:slug/incidents/:id/explain uses cached summary" do
    # Set up cached summary
    @open_issue.update!(
      ai_summary: "## Root Cause\n\nCached cause.\n\n## Suggested Fix\n\nCached fix.",
      ai_summary_generated_at: 30.minutes.ago
    )

    get "/api/v1/cli/apps/#{@project.slug}/incidents/inc_#{@open_issue.id}/explain", headers: @headers

    assert_response :success
    json = JSON.parse(response.body)
    assert_includes json["data"]["root_cause"], "Cached cause"
  end

  test "GET /api/v1/cli/apps/:slug/incidents/:id/explain generates fallback when no cache" do
    # Clear any cached summary
    @open_issue.update!(ai_summary: nil, ai_summary_generated_at: nil)

    # The AI stub is already set up in test_helper.rb via WebMock
    # The endpoint will call AiSummaryService which hits api.anthropic.com
    get "/api/v1/cli/apps/#{@project.slug}/incidents/inc_#{@open_issue.id}/explain", headers: @headers

    assert_response :success
    json = JSON.parse(response.body)

    data = json["data"]
    assert_equal "inc_#{@open_issue.id}", data["incident_id"]
    # Either has AI response or fallback - both are valid
    assert data.key?("root_cause")
    assert data.key?("confidence_score")
  end

  # =============================================================================
  # GET /api/v1/cli/apps/:slug/traces
  # =============================================================================

  test "GET /api/v1/cli/apps/:slug/traces requires endpoint param" do
    get "/api/v1/cli/apps/#{@project.slug}/traces", headers: @headers

    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "bad_request", json["error"]
    assert_includes json["message"], "endpoint"
  end

  test "GET /api/v1/cli/apps/:slug/traces returns trace data" do
    # Use existing fixture: minute_rollup has target "HomeController#index"
    @minute_rollup = perf_rollups(:minute_rollup)

    # Search for the HomeController which exists in the fixture
    get "/api/v1/cli/apps/#{@project.slug}/traces?endpoint=HomeController", headers: @headers

    assert_response :success
    json = JSON.parse(response.body)

    assert_equal "trace", json["command"]

    data = json["data"]
    assert data["trace_id"].start_with?("tr_")
    assert data.key?("endpoint")
    assert data.key?("duration_ms")
    assert data["spans"].is_a?(Array)
    assert data["bottlenecks"].is_a?(Array)
  end

  test "GET /api/v1/cli/apps/:slug/traces returns 404 for unknown endpoint" do
    get "/api/v1/cli/apps/#{@project.slug}/traces?endpoint=/nonexistent/path", headers: @headers

    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal "not_found", json["error"]
  end

  # =============================================================================
  # Response format consistency
  # =============================================================================

  test "all CLI responses include standard envelope" do
    endpoints = [
      "/api/v1/cli/apps",
      "/api/v1/cli/apps/#{@project.slug}/status",
      "/api/v1/cli/apps/#{@project.slug}/deploy_check",
      "/api/v1/cli/apps/#{@project.slug}/incidents"
    ]

    endpoints.each do |endpoint|
      get endpoint, headers: @headers
      assert_response :success, "Failed for #{endpoint}"

      json = JSON.parse(response.body)
      assert json.key?("generated_at"), "Missing generated_at for #{endpoint}"
      assert json.key?("command"), "Missing command for #{endpoint}"
      assert json.key?("data"), "Missing data for #{endpoint}"
    end
  end

  test "generated_at is valid ISO8601 timestamp" do
    get "/api/v1/cli/apps", headers: @headers

    json = JSON.parse(response.body)
    timestamp = json["generated_at"]

    # Should parse without error
    parsed = Time.parse(timestamp)
    assert parsed.is_a?(Time)

    # Should be recent (within last minute)
    assert_in_delta Time.current.to_i, parsed.to_i, 60
  end
end
