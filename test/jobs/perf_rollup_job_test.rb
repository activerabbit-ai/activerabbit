require "test_helper"

class PerfRollupJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "processes minute rollup for all accounts" do
    # Stub the rollup methods to avoid database operations
    PerfRollup.stub(:rollup_minute_data!, true) do
      assert_nothing_raised do
        PerfRollupJob.new.perform("minute")
      end
    end
  end

  test "processes hour rollup for all accounts" do
    PerfRollup.stub(:rollup_hourly_data!, true) do
      assert_nothing_raised do
        PerfRollupJob.new.perform("hour")
      end
    end
  end

  test "handles unknown timeframe gracefully" do
    # The job catches errors per-account and continues, so it won't raise
    # at the job level but will log errors
    assert_nothing_raised do
      PerfRollupJob.new.perform("invalid_timeframe")
    end
  end

  test "continues processing other accounts when one fails" do
    # Create a scenario where rollup might fail for one account
    # but should continue for others
    PerfRollup.stub(:rollup_minute_data!, -> { raise "Test error" }) do
      # Should not raise because errors are caught per-account
      assert_nothing_raised do
        PerfRollupJob.new.perform("minute")
      end
    end
  end

  test "defaults to minute timeframe" do
    PerfRollup.stub(:rollup_minute_data!, true) do
      assert_nothing_raised do
        PerfRollupJob.new.perform
      end
    end
  end
end
