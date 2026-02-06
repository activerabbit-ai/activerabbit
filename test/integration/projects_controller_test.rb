require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
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
    get projects_path
    assert_redirected_to new_user_session_path
  end

  test "GET show redirects to errors page" do
    get project_path(@project)
    assert_redirected_to project_slug_errors_path(@project.slug)
  end

  test "GET new" do
    get new_project_path
    assert_response :success
  end

  test "POST create redirects to onboarding" do
    post projects_path, params: {
      project: {
        name: "Onboarding Test Project #{SecureRandom.hex(4)}",
        environment: "production",
        url: "https://onboardingtest#{SecureRandom.hex(4)}.example.com"
      }
    }

    # Should redirect to onboarding
    assert_response :redirect
  end

  test "POST create generates API token" do
    post projects_path, params: {
      project: {
        name: "Token Test Project #{SecureRandom.hex(4)}",
        environment: "production",
        url: "https://tokentest#{SecureRandom.hex(4)}.example.com"
      }
    }

    new_project = Project.order(created_at: :desc).first
    assert new_project.api_tokens.active.any?
  end

  test "PATCH update with valid params" do
    new_name = "Updated Project Name #{SecureRandom.hex(4)}"
    patch project_path(@project), params: {
      project: { name: new_name }
    }

    assert_redirected_to project_slug_errors_path(@project.slug)
    @project.reload
    assert_equal new_name, @project.name
  end

  test "POST regenerate_token creates new token" do
    # Ensure project has a token first
    @project.generate_api_token! if @project.api_tokens.active.empty?
    
    post regenerate_token_project_path(@project)

    assert_redirected_to project_slug_errors_path(@project.slug)
    @project.reload
    assert @project.api_tokens.active.count >= 1
  end
end
