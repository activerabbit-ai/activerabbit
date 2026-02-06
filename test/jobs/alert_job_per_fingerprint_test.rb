require "test_helper"

class AlertJobPerFingerprintTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @issue = issues(:open_issue)
    @project.update!(settings: { "notifications" => { "enabled" => true } })
  end

  test "PER_FINGERPRINT_ALERT_TYPES includes new_issue" do
    assert_includes AlertJob::PER_FINGERPRINT_ALERT_TYPES, "new_issue"
  end

  test "PER_FINGERPRINT_ALERT_TYPES includes error_frequency" do
    assert_includes AlertJob::PER_FINGERPRINT_ALERT_TYPES, "error_frequency"
  end

  test "PER_FINGERPRINT_ALERT_TYPES does not include performance_regression" do
    refute_includes AlertJob::PER_FINGERPRINT_ALERT_TYPES, "performance_regression"
  end

  test "PER_FINGERPRINT_ALERT_TYPES does not include n_plus_one" do
    refute_includes AlertJob::PER_FINGERPRINT_ALERT_TYPES, "n_plus_one"
  end
end
