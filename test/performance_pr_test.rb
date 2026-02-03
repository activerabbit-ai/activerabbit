require "minitest/autorun"
require "rails/test_help"

class PerformancePrTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "test@example.com", password: "password", account: Account.first || Account.create!(name: "Test"))
    sign_in @user
    @project = @user.projects.first || @user.projects.create!(name: "Demo", slug: "demo", url: "http://example.com", environment: "production", account: @user.account)
    @project.update(settings: (@project.settings || {}).merge("github_repo" => "owner/repo", "github_pat" => "ghp_xxx"))
  end

  test "create_pr success redirects to github" do
    Github::PrService.any_instance.stubs(:create_pr_for_issue).returns({ success: true, pr_url: "https://github.com/owner/repo/pull/1" })

    post project_performance_action_create_pr_path(@project, target: "HomeController#index")
    assert_response :redirect
    assert_match %r{https://github.com/owner/repo/pull/1}, @response.redirect_url
  end

  test "create_pr failure shows alert" do
    Github::PrService.any_instance.stubs(:create_pr_for_issue).returns({ success: false, error: "Repo not found" })

    post project_performance_action_create_pr_path(@project, target: "HomeController#index")
    follow_redirect!
    assert_select "div", /Repo not found/
  end

  test "action_detail renders Open on GitHub when perf_pr_urls present" do
    pr_url = "https://github.com/owner/repo/pull/42"
    @project.update(settings: (@project.settings || {}).merge("perf_pr_urls" => { "HomeController#index" => pr_url }))

    get project_performance_action_detail_path(@project, target: "HomeController#index")
    assert_response :success
    assert_select "a[href='#{pr_url}']", text: /Open on GitHub/
  end
end
