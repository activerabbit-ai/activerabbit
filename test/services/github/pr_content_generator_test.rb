require "test_helper"

class Github::PrContentGeneratorTest < ActiveSupport::TestCase
  setup do
    @issue = issues(:open_issue)

    # Stub Anthropic API
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        body: { "content" => [{ "type" => "text", "text" => "fix: handle nil user" }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    @ai_summary = <<~SUMMARY
      ## Root Cause

      The error occurs because @user is nil when calling .foo method.

      ## Suggested Fix

      **Before:**

      ```ruby
      @user.foo
      ```

      **After:**

      ```ruby
      @user&.foo
      ```

      ## Prevention

      Always use safe navigation operator.
    SUMMARY
  end

  test "accepts anthropic_key on initialize" do
    service = Github::PrContentGenerator.new(anthropic_key: "test-key")
    assert service.is_a?(Github::PrContentGenerator)
  end

  # When issue has AI summary

  test "returns parsed PR content when issue has AI summary" do
    @issue.update!(ai_summary: @ai_summary)

    service = Github::PrContentGenerator.new(anthropic_key: "test-key")
    result = service.generate(@issue)

    assert result[:title].present?
    assert result[:body].present?
    assert result[:code_fix].present?
    assert result[:before_code].present?
  end

  test "extracts fix code from summary" do
    @issue.update!(ai_summary: @ai_summary)

    service = Github::PrContentGenerator.new(anthropic_key: "test-key")
    result = service.generate(@issue)

    assert_includes result[:code_fix], "@user&.foo"
  end

  test "extracts before code from summary" do
    @issue.update!(ai_summary: @ai_summary)

    service = Github::PrContentGenerator.new(anthropic_key: "test-key")
    result = service.generate(@issue)

    assert_includes result[:before_code], "@user.foo"
  end

  test "generates PR title from root cause" do
    @issue.update!(ai_summary: @ai_summary)

    service = Github::PrContentGenerator.new(anthropic_key: "test-key")
    result = service.generate(@issue)

    assert result[:title].start_with?("fix:")
  end

  # When issue has no AI summary and no API key

  test "returns basic fallback content without AI summary or API key" do
    @issue.update!(ai_summary: nil)

    service = Github::PrContentGenerator.new(anthropic_key: nil)
    result = service.generate(@issue)

    assert_includes result[:title], @issue.exception_class
    assert_includes result[:body], "Bug Fix"
    assert_nil result[:code_fix]
  end

  # parse_ai_summary

  test "parse_ai_summary extracts root cause section" do
    service = Github::PrContentGenerator.new(anthropic_key: "test-key")
    result = service.send(:parse_ai_summary, @ai_summary)

    assert_includes result[:root_cause], "@user is nil"
  end

  test "parse_ai_summary extracts fix section" do
    service = Github::PrContentGenerator.new(anthropic_key: "test-key")
    result = service.send(:parse_ai_summary, @ai_summary)

    assert result[:fix].present?
  end

  test "parse_ai_summary extracts fix code" do
    service = Github::PrContentGenerator.new(anthropic_key: "test-key")
    result = service.send(:parse_ai_summary, @ai_summary)

    assert_includes result[:fix_code], "@user&.foo"
  end

  test "parse_ai_summary extracts before code" do
    service = Github::PrContentGenerator.new(anthropic_key: "test-key")
    result = service.send(:parse_ai_summary, @ai_summary)

    assert_includes result[:before_code], "@user.foo"
  end

  test "parse_ai_summary extracts prevention section" do
    service = Github::PrContentGenerator.new(anthropic_key: "test-key")
    result = service.send(:parse_ai_summary, @ai_summary)

    assert_includes result[:prevention], "safe navigation"
  end

  test "parse_ai_summary handles empty summary" do
    service = Github::PrContentGenerator.new(anthropic_key: "test-key")
    result = service.send(:parse_ai_summary, "")

    assert_nil result[:root_cause]
    assert_nil result[:fix]
    assert_nil result[:fix_code]
  end

  # validate_method_structure

  test "validate_method_structure returns true for valid method" do
    service = Github::PrContentGenerator.new(anthropic_key: "test-key")
    code = "def show\n  @user = User.find(params[:id])\nend"

    assert service.send(:validate_method_structure, code)
  end

  test "validate_method_structure returns false for blank code" do
    service = Github::PrContentGenerator.new(anthropic_key: "test-key")

    refute service.send(:validate_method_structure, "")
  end
end
