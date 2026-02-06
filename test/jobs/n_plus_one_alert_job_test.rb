require "test_helper"

class NPlusOneAlertJobTest < ActiveSupport::TestCase
  setup do
    @project = projects(:default)
  end

  test "checks N+1 alert rules for project" do
    incidents = [
      {
        sql_fingerprint: sql_fingerprints(:user_select),
        count_in_request: 10,
        controller_action: "UsersController#index",
        severity: "medium"
      }
    ]

    AlertRule.stub(:check_n_plus_one_rules, true) do
      assert_nothing_raised do
        NPlusOneAlertJob.new.perform(@project.id, incidents)
      end
    end
  end

  test "handles project not found gracefully" do
    incidents = [{ severity: "low" }]

    # Should not raise, just log and return
    assert_nothing_raised do
      NPlusOneAlertJob.new.perform(999999, incidents)
    end
  end

  test "handles empty incidents array" do
    AlertRule.stub(:check_n_plus_one_rules, true) do
      assert_nothing_raised do
        NPlusOneAlertJob.new.perform(@project.id, [])
      end
    end
  end
end
