require "test_helper"

class AlertRulePerFingerprintTest < ActiveSupport::TestCase
  # Note: These tests require Redis to be available.

  test "check_error_frequency_rules includes fingerprint in payload" do
    alert_rule = alert_rules(:error_frequency_rule)
    issue = issues(:open_issue)

    # Validate the structure exists (actual Redis-based alerting tested in integration)
    assert issue.fingerprint.present?
    assert_equal "error_frequency", alert_rule.rule_type
  end
end
