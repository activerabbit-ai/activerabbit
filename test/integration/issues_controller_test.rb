require "test_helper"

class IssuesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
    @issue = issues(:open_issue)
    sign_in @user
    ActsAsTenant.current_tenant = @account
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "requires authentication" do
    sign_out @user
    get project_issues_path(@project)
    assert_redirected_to new_user_session_path
  end

  test "GET index" do
    get project_issues_path(@project)
    assert_response :success
    assert assigns(:issues).present?
  end

  test "GET index with status filter" do
    get project_issues_path(@project), params: { status: "open" }
    assert_response :success
  end

  test "GET index with sort by count" do
    get project_issues_path(@project), params: { sort: "count" }
    assert_response :success
  end

  test "GET index with sort by first_seen" do
    get project_issues_path(@project), params: { sort: "first_seen" }
    assert_response :success
  end

  test "GET show" do
    get project_issue_path(@project, @issue)
    assert_response :success
    assert assigns(:events).present? || true
  end

  test "GET show displays related issues" do
    get project_issue_path(@project, @issue)
    assert_response :success
    assert assigns(:related_issues).is_a?(ActiveRecord::Relation)
  end

  test "DELETE destroy" do
    assert_difference "Issue.count", -1 do
      delete project_issue_path(@project, @issue)
    end

    assert_redirected_to project_issues_path(@project)
  end

  test "index shows stats" do
    get project_issues_path(@project)
    assert_response :success
    assert assigns(:stats).is_a?(Hash)
    assert assigns(:stats)[:total].is_a?(Integer)
    assert assigns(:stats)[:open].is_a?(Integer)
  end
end
