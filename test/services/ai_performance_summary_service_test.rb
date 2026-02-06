require "test_helper"

class AiPerformanceSummaryServiceTest < ActiveSupport::TestCase
  setup do
    @target = "UsersController#index"
    @stats = {
      avg_duration: 2500,
      p95_duration: 5000,
      request_count: 100,
      slow_endpoints: [
        { endpoint: "/api/users", avg_duration: 2500, p95_duration: 5000 }
      ]
    }
  end

  test "accepts target and stats on initialize" do
    service = AiPerformanceSummaryService.new(target: @target, stats: @stats)
    assert service.is_a?(AiPerformanceSummaryService)
  end

  test "accepts optional sample_event" do
    event = events(:default)
    service = AiPerformanceSummaryService.new(target: @target, stats: @stats, sample_event: event)
    assert service.is_a?(AiPerformanceSummaryService)
  end

  # When ANTHROPIC_API_KEY is missing

  test "call returns missing_api_key error when no API key" do
    original_key = ENV["ANTHROPIC_API_KEY"]
    ENV["ANTHROPIC_API_KEY"] = nil

    service = AiPerformanceSummaryService.new(target: @target, stats: @stats)
    result = service.call

    assert_equal "missing_api_key", result[:error]
  ensure
    ENV["ANTHROPIC_API_KEY"] = original_key
  end

  # When ANTHROPIC_API_KEY is present

  test "call returns performance summary" do
    api_response = {
      "content" => [{
        "type" => "text",
        "text" => "## Performance Analysis\n\nThe endpoint is slow due to..."
      }]
    }

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, body: api_response.to_json, headers: { "Content-Type" => "application/json" })

    ENV["ANTHROPIC_API_KEY"] = "test-api-key"
    service = AiPerformanceSummaryService.new(target: @target, stats: @stats)
    result = service.call

    assert_includes result[:summary], "Performance Analysis"
  ensure
    ENV["ANTHROPIC_API_KEY"] = nil
  end
end
