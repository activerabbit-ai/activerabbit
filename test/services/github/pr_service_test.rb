require "test_helper"

class Github::PrServiceTest < ActiveSupport::TestCase
  setup do
    @project = projects(:default)
    @project.update!(settings: {
      "github_repo" => "owner/repo",
      "github_pat" => "test-pat-token"
    })
    @issue = issues(:open_issue)
    @issue.update!(
      ai_summary: "## Root Cause\n\nTest\n\n## Fix\n\n```ruby\n@user&.foo\n```"
    )
  end

  test "accepts project on initialize" do
    service = Github::PrService.new(@project)
    assert service.is_a?(Github::PrService)
  end

  test "configured returns true when github_repo is set" do
    service = Github::PrService.new(@project)
    assert service.send(:configured?)
  end

  test "configured returns false when github_repo is missing" do
    @project.update!(settings: {})
    service = Github::PrService.new(@project)

    refute service.send(:configured?)
  end

  # create_pr_for_issue

  test "create_pr_for_issue returns error when not configured" do
    @project.update!(settings: {})
    service = Github::PrService.new(@project)

    result = service.create_pr_for_issue(@issue)

    refute result[:success]
    assert_includes result[:error], "not configured"
  end

  # create_n_plus_one_fix_pr

  test "create_n_plus_one_fix_pr returns error when not configured" do
    @project.update!(settings: {})
    service = Github::PrService.new(@project)
    sql_fingerprint = OpenStruct.new(id: 1, fingerprint: "SELECT * FROM users")

    result = service.create_n_plus_one_fix_pr(sql_fingerprint)

    refute result[:success]
    assert_includes result[:error], "not configured"
  end
end
