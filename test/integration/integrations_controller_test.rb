require "test_helper"

class IntegrationsControllerTest < ActionDispatch::IntegrationTest
  test "GET slack does not require authentication" do
    get slack_integration_path
    assert_response :success
  end

  test "GET slack shows Slack integration page" do
    get slack_integration_path
    assert_response :success
  end

  test "GET slack sets slack_client_id from ENV" do
    # Set a test client ID
    original_env = ENV["SLACK_CLIENT_ID"]
    ENV["SLACK_CLIENT_ID"] = "test-client-id"

    get slack_integration_path
    assert_response :success
    assert_equal "test-client-id", assigns(:slack_client_id)

    # Restore original ENV
    ENV["SLACK_CLIENT_ID"] = original_env
  end
end
