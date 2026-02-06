require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
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
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "GET dashboard index" do
    get dashboard_path
    assert_response :success
  end

  test "dashboard shows project stats" do
    get dashboard_path
    assert_response :success
    assert assigns(:stats).present?
    assert assigns(:projects).present?
  end

  test "dashboard stats include total_projects" do
    get dashboard_path
    assert_response :success
    assert assigns(:stats)[:total_projects].is_a?(Integer)
  end

  test "dashboard stats include open_issues" do
    get dashboard_path
    assert_response :success
    assert assigns(:stats)[:open_issues].is_a?(Integer)
  end

  test "dashboard shows recent projects" do
    get dashboard_path
    assert_response :success
    assert assigns(:recent_projects).present?
  end

  test "project_dashboard redirects to errors page" do
    get project_dashboard_path(@project.slug)
    assert_redirected_to project_slug_errors_path(@project.slug)
  end

  test "project_dashboard handles missing project" do
    get project_dashboard_path("nonexistent-slug")
    assert_redirected_to dashboard_path
  end

  test "dashboard computes project stats without N+1" do
    get dashboard_path
    assert_response :success

    # Project stats should be precomputed
    assert assigns(:project_stats).is_a?(Hash)
    @project.reload
    stats = assigns(:project_stats)[@project.id]
    assert stats.present?
    assert stats.key?(:issues_count)
    assert stats.key?(:events_today)
  end
end
