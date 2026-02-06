require "test_helper"

class ApiDeploysTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
    @token = api_tokens(:default)
    @headers = { "CONTENT_TYPE" => "application/json", "X-Project-Token" => @token.token }
  end

  test "POST /api/v1/deploys creates a deploy and associated release" do
    body = {
      project_slug: @project.slug,
      version: "v#{SecureRandom.hex(4)}",
      environment: "production",
      status: "success",
      user: @user.email,
      started_at: 1.minute.ago.iso8601,
      finished_at: Time.current.iso8601
    }.to_json

    assert_difference -> { Deploy.count }, 1 do
      post "/api/v1/deploys", params: body, headers: @headers
    end

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal true, json["ok"]
    assert json["deploy_id"].present?
  end

  test "POST /api/v1/deploys returns not_found for unknown project slug" do
    body = {
      project_slug: "missing-project",
      version: "v1.0.0",
      environment: "production",
      status: "success",
      user: @user.email
    }.to_json

    post "/api/v1/deploys", params: body, headers: @headers

    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal "not_found", json["error"]
  end

  test "POST /api/v1/deploys returns not_found for unknown user email" do
    body = {
      project_slug: @project.slug,
      version: "v1.0.0",
      environment: "production",
      status: "success",
      user: "missing@example.com"
    }.to_json

    post "/api/v1/deploys", params: body, headers: @headers

    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal "not_found", json["error"]
  end
end
