require "test_helper"

class AiPerformanceSummaryServiceTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
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

  test "accepts account, target, and stats on initialize" do
    service = AiPerformanceSummaryService.new(account: @account, target: @target, stats: @stats)
    assert service.is_a?(AiPerformanceSummaryService)
  end

  test "accepts optional sample_event" do
    event = events(:default)
    service = AiPerformanceSummaryService.new(account: @account, target: @target, stats: @stats, sample_event: event)
    assert service.is_a?(AiPerformanceSummaryService)
  end

  test "call returns missing_config error when no AI provider configured" do
    service = AiPerformanceSummaryService.new(account: @account, target: @target, stats: @stats)
    result = service.call

    assert_equal "missing_config", result[:error]
  end
end
