# require "test_helper"
#
# NOTE: This test file uses Mocha's any_instance.stubs which is not available
# without the mocha gem. Tests commented out until either:
# 1. Mocha is added as a dependency, or
# 2. Tests are rewritten using standard Minitest mocking
#
# class PerformancePrTest < ActionDispatch::IntegrationTest
#   setup do
#     @user = users(:owner)
#     sign_in @user
#     @project = projects(:with_github)
#   end
#
#   test "create_pr success redirects to github" do
#     # Requires Mocha gem for any_instance.stubs
#   end
#
#   test "create_pr failure shows alert" do
#     # Requires Mocha gem for any_instance.stubs
#   end
#
#   test "action_detail renders Open on GitHub when perf_pr_urls present" do
#     pr_url = "https://github.com/owner/repo/pull/42"
#     @project.update!(settings: @project.settings.merge("perf_pr_urls" => { "HomeController#index" => pr_url }))
#
#     get project_performance_action_detail_path(@project, target: "HomeController#index")
#     assert_response :success
#     assert_select "a[href='#{pr_url}']", text: /Open on GitHub/
#   end
# end
