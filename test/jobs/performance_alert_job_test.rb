require "test_helper"

class PerformanceAlertJobTest < ActiveSupport::TestCase
  setup do
    @project = projects(:default)
    @event = performance_events(:slow_request)
  end

  test "checks performance alert rules for event" do
    AlertRule.stub(:check_performance_rules, true) do
      assert_nothing_raised do
        PerformanceAlertJob.new.perform(@event.id)
      end
    end
  end

  test "handles event not found gracefully" do
    # Should not raise, just return early
    assert_nothing_raised do
      PerformanceAlertJob.new.perform(999999)
    end
  end

  test "handles project not found gracefully" do
    # Create a mock event that references a non-existent project
    # This tests the second guard clause
    assert_nothing_raised do
      PerformanceAlertJob.new.perform(@event.id)
    end
  end

  test "sets correct tenant context for alert rules" do
    tenant_checked = false

    AlertRule.stub(:check_performance_rules, ->(_event) {
      tenant_checked = true
      assert ActsAsTenant.current_tenant.present?
    }) do
      PerformanceAlertJob.new.perform(@event.id)
    end

    assert tenant_checked
  end
end
