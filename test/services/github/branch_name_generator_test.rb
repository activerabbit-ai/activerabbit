require "test_helper"

class Github::BranchNameGeneratorTest < ActiveSupport::TestCase
  setup do
    @issue = issues(:open_issue)

    # Stub Anthropic API for all tests
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        body: { "content" => [{ "type" => "text", "text" => "ai-fix/runtime-error-fix" }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  test "accepts anthropic_key on initialize" do
    service = Github::BranchNameGenerator.new(anthropic_key: "test-key")
    assert service.is_a?(Github::BranchNameGenerator)
  end

  # Custom branch name tests

  test "returns sanitized custom branch name with prefix" do
    service = Github::BranchNameGenerator.new(anthropic_key: "test-key")
    result = service.generate(@issue, "my-custom-branch")

    assert_equal "ai-fix/my-custom-branch", result
  end

  test "sanitizes invalid characters in branch name" do
    service = Github::BranchNameGenerator.new(anthropic_key: "test-key")
    result = service.generate(@issue, "My Branch Name!")

    assert_equal "ai-fix/my-branch-name", result
  end

  test "handles spaces and special characters" do
    service = Github::BranchNameGenerator.new(anthropic_key: "test-key")
    result = service.generate(@issue, "fix: user login issue")

    refute_includes result, " "
    refute_includes result, ":"
  end

  test "preserves existing prefix" do
    service = Github::BranchNameGenerator.new(anthropic_key: "test-key")
    result = service.generate(@issue, "fix/my-branch")

    assert_equal "fix/my-branch", result
  end

  # AI generation tests

  test "generates branch name via AI" do
    api_response = {
      "content" => [{
        "type" => "text",
        "text" => "ai-fix/runtime-error-home-index"
      }]
    }

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, body: api_response.to_json, headers: { "Content-Type" => "application/json" })

    service = Github::BranchNameGenerator.new(anthropic_key: "test-key")
    result = service.generate(@issue)

    assert result.present?
    assert_match(/^ai-fix\//, result)
  end

  test "generates fallback branch name without API key" do
    service = Github::BranchNameGenerator.new(anthropic_key: nil)
    result = service.generate(@issue)

    assert result.present?
    assert result.start_with?("ai-fix/")
  end

  test "falls back to generated name when AI fails" do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 500, body: "Internal Server Error")

    service = Github::BranchNameGenerator.new(anthropic_key: "test-key")
    result = service.generate(@issue)

    assert result.present?
    assert_includes result, "fix"
  end

  # Branch name format validation

  test "produces valid git branch name" do
    api_response = {
      "content" => [{
        "type" => "text",
        "text" => "ai-fix/runtime-error-home-index"
      }]
    }

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, body: api_response.to_json, headers: { "Content-Type" => "application/json" })

    service = Github::BranchNameGenerator.new(anthropic_key: "test-key")
    result = service.generate(@issue)

    refute result.start_with?("-")
    refute result.end_with?("-")
    refute_includes result, " "
    refute_includes result, ".."
    assert_match(/^[a-z0-9\-\/]+$/i, result)
  end

  test "branch name is reasonably short" do
    api_response = {
      "content" => [{
        "type" => "text",
        "text" => "ai-fix/short-name"
      }]
    }

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, body: api_response.to_json, headers: { "Content-Type" => "application/json" })

    service = Github::BranchNameGenerator.new(anthropic_key: "test-key")
    result = service.generate(@issue)

    assert result.length <= 100
  end
end
