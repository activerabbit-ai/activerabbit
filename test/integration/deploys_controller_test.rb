require "test_helper"

class DeploysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
    sign_in @user
    ActsAsTenant.current_tenant = @account
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "requires authentication" do
    sign_out @user
    get project_deploys_path(@project)
    assert_redirected_to new_user_session_path
  end

  test "GET index with project shows project deploys" do
    get project_deploys_path(@project)
    assert_response :success
    assert assigns(:project_scope).present?
    assert assigns(:deploys).is_a?(Array)
  end

  test "index calculates max_live_seconds" do
    get project_deploys_path(@project)
    assert_response :success
    assert assigns(:max_live_seconds).is_a?(Numeric)
  end

  test "index calculates max_errors" do
    get project_deploys_path(@project)
    assert_response :success
    assert assigns(:max_errors).is_a?(Numeric)
  end

  test "index calculates max_errors_per_hour" do
    get project_deploys_path(@project)
    assert_response :success
    assert assigns(:max_errors_per_hour).is_a?(Numeric)
  end
end
