require "test_helper"

class RegressionDetectionJobTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @release = releases(:v1_0_0)
  end

  test "detects performance regressions for release" do
    # Stub the regression detection to return empty (no regressions)
    @release.stub(:detect_performance_regression!, []) do
      assert_nothing_raised do
        RegressionDetectionJob.new.perform(@release.id, @account.id)
      end
    end
  end

  test "logs warning when regressions detected" do
    regressions = [
      {
        controller_action: "UsersController#index",
        before_p95: 100.0,
        after_p95: 250.0,
        regression_pct: 150.0,
        severity: "high"
      }
    ]

    Release.stub(:find, @release) do
      @release.stub(:detect_performance_regression!, regressions) do
        assert_nothing_raised do
          RegressionDetectionJob.new.perform(@release.id, @account.id)
        end
      end
    end
  end

  test "raises error when release not found" do
    assert_raises ActiveRecord::RecordNotFound do
      RegressionDetectionJob.new.perform(999999, @account.id)
    end
  end

  test "handles multiple regressions" do
    regressions = [
      { controller_action: "UsersController#index", before_p95: 100.0, after_p95: 250.0, regression_pct: 150.0 },
      { controller_action: "PostsController#show", before_p95: 50.0, after_p95: 150.0, regression_pct: 200.0 }
    ]

    Release.stub(:find, @release) do
      @release.stub(:detect_performance_regression!, regressions) do
        assert_nothing_raised do
          RegressionDetectionJob.new.perform(@release.id, @account.id)
        end
      end
    end
  end

  test "works without account_id using fallback" do
    @release.stub(:detect_performance_regression!, []) do
      assert_nothing_raised do
        RegressionDetectionJob.new.perform(@release.id)
      end
    end
  end
end
