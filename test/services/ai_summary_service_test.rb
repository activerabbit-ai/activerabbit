require "test_helper"

class AiSummaryServiceTest < ActiveSupport::TestCase
  setup do
    @issue = issues(:open_issue)
    @event = events(:default)
    @event.update!(
      context: {
        "structured_stack_trace" => [
          {
            "file" => "app/controllers/users_controller.rb",
            "line" => 25,
            "method" => "show",
            "in_app" => true,
            "source_context" => {
              "lines_before" => ["  def show", "    @user = User.find(params[:id])"],
              "line_content" => "    @user.foo",
              "lines_after" => ["  end"]
            }
          }
        ]
      }
    )
  end

  test "accepts issue and sample_event on initialize" do
    service = AiSummaryService.new(issue: @issue, sample_event: @event)
    assert service.is_a?(AiSummaryService)
  end

  test "accepts optional github_client" do
    github_client = Object.new
    service = AiSummaryService.new(issue: @issue, sample_event: @event, github_client: github_client)
    assert service.is_a?(AiSummaryService)
  end

  # When ANTHROPIC_API_KEY is missing

  test "call returns missing_api_key error when no API key" do
    original_key = ENV["ANTHROPIC_API_KEY"]
    ENV["ANTHROPIC_API_KEY"] = nil

    service = AiSummaryService.new(issue: @issue, sample_event: @event)
    result = service.call

    assert_equal "missing_api_key", result[:error]
    assert_includes result[:message], "ANTHROPIC_API_KEY"
  ensure
    ENV["ANTHROPIC_API_KEY"] = original_key
  end

  # When ANTHROPIC_API_KEY is present

  test "call returns AI summary" do
    api_response = {
      "content" => [{
        "type" => "text",
        "text" => "## Root Cause\n\nThe error occurs because...\n\n## Fix\n\n**Before:**\n\n```ruby\n@user.foo\n```\n\n**After:**\n\n```ruby\n@user&.foo\n```\n\n## Prevention\n\nUse safe navigation."
      }]
    }

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, body: api_response.to_json, headers: { "Content-Type" => "application/json" })

    ENV["ANTHROPIC_API_KEY"] = "test-api-key"
    service = AiSummaryService.new(issue: @issue, sample_event: @event)
    result = service.call

    assert_includes result[:summary], "Root Cause"
    assert_includes result[:summary], "Fix"
  ensure
    ENV["ANTHROPIC_API_KEY"] = nil
  end

  test "call returns ai_error when API fails" do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 500, body: "Internal Server Error")

    ENV["ANTHROPIC_API_KEY"] = "test-api-key"
    service = AiSummaryService.new(issue: @issue, sample_event: @event)
    result = service.call

    assert_equal "ai_error", result[:error]
  ensure
    ENV["ANTHROPIC_API_KEY"] = nil
  end

  # SYSTEM_PROMPT

  test "SYSTEM_PROMPT includes required format instructions" do
    assert_includes AiSummaryService::SYSTEM_PROMPT, "## Root Cause"
    assert_includes AiSummaryService::SYSTEM_PROMPT, "## Suggested Fix"
    assert_includes AiSummaryService::SYSTEM_PROMPT, "## Prevention"
  end

  test "SYSTEM_PROMPT requires precise fix format with file and line" do
    assert_includes AiSummaryService::SYSTEM_PROMPT, "### File 1:"
    assert_includes AiSummaryService::SYSTEM_PROMPT, "**Line:**"
  end
end
