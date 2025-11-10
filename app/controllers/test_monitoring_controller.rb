class TestMonitoringController < ApplicationController
  # Skip authentication for testing
  skip_before_action :authenticate_user!
  skip_before_action :set_current_tenant
  skip_before_action :check_onboarding_needed

  def test_error
    # Generate a test error
    raise StandardError, "This is a test error for ActiveRabbit self-monitoring"
  end

  def test_performance
    # Simulate some slow operations
    sleep(0.5) # 500ms delay

    # Simulate database queries
    User.count
    Account.count
    Project.count

    render json: {
      message: "Performance test completed",
      timestamp: Time.current,
      operations: ["sleep 500ms", "User.count", "Account.count", "Project.count"]
    }
  end

  def test_manual_tracking
    begin
      # Test manual error tracking
      ActiveRabbit::Client.track_exception(
        StandardError.new("Manual test error"),
        context: { test: true, controller: "TestMonitoringController" },
        user_id: "test_user_123",
        tags: { environment: "development", test: true }
      )

      # Test manual performance tracking
      ActiveRabbit::Client.track_performance(
        "manual_test_operation",
        250, # 250ms
        metadata: { operation: "manual_test", controller: "TestMonitoringController" }
      )

      render json: {
        message: "Manual tracking test completed successfully",
        timestamp: Time.current
      }
    rescue => e
      render json: {
        error: "Manual tracking failed",
        message: e.message,
        backtrace: e.backtrace.first(5)
      }
    end
  end

  def test_connection
    begin
      result = ActiveRabbit::Client.test_connection
      render json: {
        status: "success",
        message: "Connection test completed",
        result: result,
        timestamp: Time.current
      }
    rescue => e
      render json: {
        status: "error",
        message: e.message,
        backtrace: e.backtrace.first(5),
        timestamp: Time.current
      }
    end
  end

  def index
    # Try to get the actual configuration from the gem
    gem_project_id = nil
    gem_api_key = nil
    begin
      if defined?(ActiveRabbit::Client) && ActiveRabbit::Client.respond_to?(:configuration)
        gem_project_id = ActiveRabbit::Client.configuration&.project_id
        gem_api_key = ActiveRabbit::Client.configuration&.api_key&.first(10) + "..." if ActiveRabbit::Client.configuration&.api_key
      end
    rescue => e
      # Ignore errors when trying to access configuration
    end

    render json: {
      message: "ActiveRabbit Self-Monitoring Test Endpoints",
      endpoints: {
        test_error: "/test_monitoring/error",
        test_performance: "/test_monitoring/performance",
        test_manual_tracking: "/test_monitoring/manual",
        test_connection: "/test_monitoring/connection"
      },
      env_project_id: ENV["ACTIVERABBIT_SELF_MONITOR_PROJECT_ID"],
      gem_project_id: gem_project_id,
      gem_api_key: gem_api_key,
      gem_configured: defined?(ActiveRabbit::Client),
      timestamp: Time.current
    }
  end

  def health_test
    # Simple health check that bypasses authentication
    render json: { status: "ok", timestamp: Time.current.iso8601 }, status: :ok
  end
end
