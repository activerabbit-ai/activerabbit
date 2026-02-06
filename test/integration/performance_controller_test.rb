require "test_helper"

class PerformanceControllerTest < ActionDispatch::IntegrationTest
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
    get performance_path
    assert_redirected_to new_user_session_path
  end

  test "GET index without project shows global overview" do
    get performance_path
    assert_response :success
    assert assigns(:projects).present?
    assert assigns(:metrics).present?
  end

  test "GET index with project shows project performance" do
    get project_performance_path(@project)
    assert_response :success
    assert assigns(:metrics).present?
  end

  test "GET index with timeframe parameter" do
    get project_performance_path(@project), params: { timeframe: "hour" }
    assert_response :success
  end

  test "GET index with hours_back parameter" do
    get project_performance_path(@project), params: { hours_back: 48 }
    assert_response :success
  end

  test "GET index with filter parameter" do
    get project_performance_path(@project), params: { filter: "slow" }
    assert_response :success
  end

  test "GET index with search query" do
    get project_performance_path(@project), params: { q: "Users" }
    assert_response :success
  end

  test "GET index with sort parameter" do
    get project_performance_path(@project), params: { sort: "avg_response_time_desc" }
    assert_response :success
  end

  test "GET index with graph tab" do
    get project_performance_path(@project), params: { tab: "graph" }
    assert_response :success
  end

  test "GET index with graph tab and range" do
    get project_performance_path(@project), params: { tab: "graph", range: "24H" }
    assert_response :success
  end

  test "action_detail shows action performance" do
    # The route requires target in the path: /projects/:project_id/performance/actions/:target
    get "/projects/#{@project.id}/performance/actions/UsersController%23index"
    assert_response :success
  end

  test "action_detail with samples tab" do
    get "/projects/#{@project.id}/performance/actions/UsersController%23index", params: { tab: "samples" }
    assert_response :success
  end

  test "action_detail with graph tab" do
    get "/projects/#{@project.id}/performance/actions/UsersController%23index", params: { tab: "graph" }
    assert_response :success
  end

  test "metrics include response_time" do
    get project_performance_path(@project)
    assert_response :success
    assert assigns(:metrics).key?(:response_time)
  end

  test "metrics include throughput" do
    get project_performance_path(@project)
    assert_response :success
    assert assigns(:metrics).key?(:throughput)
  end

  test "metrics include error_rate" do
    get project_performance_path(@project)
    assert_response :success
    assert assigns(:metrics).key?(:error_rate)
  end
end
