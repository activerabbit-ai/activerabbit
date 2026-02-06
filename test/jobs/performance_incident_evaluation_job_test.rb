require "test_helper"

class PerformanceIncidentEvaluationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @project.update!(active: true)

    # Clear existing rollups to start fresh
    PerfRollup.delete_all
  end

  test "does not create incidents without recent rollup data" do
    assert_no_difference -> { PerformanceIncident.count } do
      PerformanceIncidentEvaluationJob.new.perform
    end
  end

  test "skips inactive projects" do
    @project.update!(active: false)

    # Create rollup data
    PerfRollup.create!(
      account: @account,
      project: @project,
      target: "UsersController#index",
      timeframe: "minute",
      timestamp: 1.minute.ago,
      p95_duration_ms: 900.0
    )

    # Should not evaluate
    assert_nothing_raised do
      PerformanceIncidentEvaluationJob.new.perform
    end
  end
end
