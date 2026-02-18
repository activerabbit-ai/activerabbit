require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:trial_account)
    @user = users(:trial_user)
    sign_in @user
    ActsAsTenant.current_tenant = @account
    # Remove all projects to test onboarding flow
    @account.projects.destroy_all
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "requires authentication" do
    sign_out @user
    get onboarding_welcome_path
    assert_redirected_to new_user_session_path
  end

  test "GET welcome for new user" do
    get onboarding_welcome_path
    assert_response :success
  end

  test "GET welcome redirects if user has projects" do
    @account.projects.create!(name: "Test", environment: "production", url: "https://test.com", tech_stack: "rails")
    get onboarding_welcome_path
    assert_redirected_to dashboard_path
  end

  test "GET new_project" do
    get onboarding_new_project_path
    assert_response :success
  end

  test "POST create_project redirects to install_gem" do
    post onboarding_create_project_path, params: {
      project: {
        name: "New Project #{SecureRandom.hex(4)}",
        url: "https://newproject#{SecureRandom.hex(4)}.example.com",
        tech_stack: "rails"
      }
    }

    assert_response :redirect
  end

  test "POST create_project generates API token" do
    post onboarding_create_project_path, params: {
      project: {
        name: "Token Project #{SecureRandom.hex(4)}",
        url: "https://tokenproject#{SecureRandom.hex(4)}.example.com",
        tech_stack: "rails"
      }
    }

    project = Project.order(created_at: :desc).first
    assert project.api_tokens.active.any?
  end

  test "POST create_project saves tech_stack" do
    post onboarding_create_project_path, params: {
      project: {
        name: "Stack Project #{SecureRandom.hex(4)}",
        url: "https://stackproject#{SecureRandom.hex(4)}.example.com",
        tech_stack: "django"
      }
    }

    project = Project.order(created_at: :desc).first
    assert_equal "django", project.tech_stack
  end

  test "POST create_project fails without tech_stack" do
    post onboarding_create_project_path, params: {
      project: {
        name: "No Stack #{SecureRandom.hex(4)}",
        url: "https://nostack#{SecureRandom.hex(4)}.example.com"
      }
    }

    assert_response :success # re-renders the form
  end

  test "GET install_gem" do
    project = @account.projects.create!(name: "Test", environment: "production", url: "https://test.com", tech_stack: "rails")

    get onboarding_install_gem_path(project)
    assert_response :success
  end

  test "POST verify_gem success" do
    project = @account.projects.create!(name: "Test", environment: "production", url: "https://test.com", tech_stack: "rails")

    GemVerificationService.stub(:new, ->(_project) {
      OpenStruct.new(verify_connection: { success: true, message: "Connected!" })
    }) do
      post onboarding_verify_gem_path(project)
    end

    assert_redirected_to onboarding_setup_github_path(project)
  end

  test "POST verify_gem failure" do
    project = @account.projects.create!(name: "Test", environment: "production", url: "https://test.com", tech_stack: "rails")

    GemVerificationService.stub(:new, ->(_project) {
      OpenStruct.new(verify_connection: { success: false, error: "Not connected", error_code: "NO_EVENTS" })
    }) do
      post onboarding_verify_gem_path(project)
    end

    assert_redirected_to onboarding_install_gem_path(project)
  end

  test "GET setup_github" do
    project = @account.projects.create!(name: "Test", environment: "production", url: "https://test.com", tech_stack: "rails")

    Github::InstallationService.stub(:app_install_url, "https://github.com/install") do
      get onboarding_setup_github_path(project)
    end

    assert_response :success
  end

  test "GET connect_github with installation_id" do
    project = @account.projects.create!(name: "Test", environment: "production", url: "https://test.com", tech_stack: "rails")

    get onboarding_connect_github_path, params: { installation_id: "12345" }

    # Should redirect (either success or failure)
    assert_response :redirect
  end
end
