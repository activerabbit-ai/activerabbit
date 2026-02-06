require "test_helper"

class ApiReleasesTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @token = api_tokens(:default)
    @headers = { "CONTENT_TYPE" => "application/json", "X-Project-Token" => @token.token }
  end

  test "POST /api/v1/releases creates a release" do
    body = { version: "v1.2.3", environment: "production" }.to_json

    post "/api/v1/releases", params: body, headers: @headers

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal "v1.2.3", json["data"]["version"]
  end

  test "POST /api/v1/releases conflicts on duplicate" do
    post "/api/v1/releases", params: { version: "v999.0.0" }.to_json, headers: @headers
    post "/api/v1/releases", params: { version: "v999.0.0" }.to_json, headers: @headers

    assert_response :conflict
  end

  test "GET /api/v1/releases lists releases" do
    get "/api/v1/releases", headers: @headers

    assert_response :ok
    json = JSON.parse(response.body)
    assert json["data"].is_a?(Array)
  end

  test "GET /api/v1/releases/:id shows a release" do
    release = releases(:v1_0_0)

    get "/api/v1/releases/#{release.id}", headers: @headers

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal release.version, json["data"]["version"]
  end

  test "POST /api/v1/releases/:id/trigger_regression_check queues regression check" do
    release = releases(:v1_0_0)

    post "/api/v1/releases/#{release.id}/trigger_regression_check", headers: @headers

    assert_response :ok
    json = JSON.parse(response.body)
    assert_match(/queued/i, json["message"])
  end
end
