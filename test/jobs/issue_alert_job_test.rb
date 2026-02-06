require "test_helper"

class IssueAlertJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @project = projects(:default)
    @issue = issues(:open_issue)
    @issue.update!(fingerprint: "test-fingerprint-#{SecureRandom.hex(8)}", count: 1, first_seen_at: Time.current)

    # Use existing or find/create alert rule (has uniqueness on project+rule_type)
    AlertRule.find_or_create_by!(
      account: @account,
      project: @project,
      rule_type: "new_issue"
    ) do |rule|
      rule.name = "New Issue Alert"
      rule.threshold_value = 1
      rule.time_window_minutes = 5
      rule.enabled = true
    end

    # Use existing or find/create notification preference (has uniqueness on project+alert_type)
    NotificationPreference.find_or_create_by!(
      project: @project,
      alert_type: "new_issue"
    ) do |pref|
      pref.frequency = "every_30_minutes"
      pref.enabled = true
    end

    # Clear Redis rate limit (skip if Redis unavailable)
    begin
      redis.del("issue_rate_limit:#{@project.id}:new_issue:#{@issue.fingerprint}")
    rescue Redis::CannotConnectError, Errno::ECONNREFUSED
      # Redis not available - tests will still work
    end
  end

  # frequency_to_minutes

  test "frequency_to_minutes returns 5 for immediate" do
    job = IssueAlertJob.new
    assert_equal 5, job.send(:frequency_to_minutes, "immediate")
  end

  test "frequency_to_minutes returns 30 for every_30_minutes" do
    job = IssueAlertJob.new
    assert_equal 30, job.send(:frequency_to_minutes, "every_30_minutes")
  end

  test "frequency_to_minutes returns 120 for every_2_hours" do
    job = IssueAlertJob.new
    assert_equal 120, job.send(:frequency_to_minutes, "every_2_hours")
  end

  test "frequency_to_minutes returns 30 as default" do
    job = IssueAlertJob.new
    assert_equal 30, job.send(:frequency_to_minutes, nil)
    assert_equal 30, job.send(:frequency_to_minutes, "unknown")
  end

  # first_occurrence_in_deploy?

  test "first_occurrence_in_deploy returns true for issues created after deploy" do
    release = Release.find_or_create_by!(
      account: @account,
      project: @project,
      version: "v#{SecureRandom.hex(4)}"
    ) do |r|
      r.deployed_at = 1.hour.ago
    end
    @issue.update!(first_seen_at: 30.minutes.ago)

    job = IssueAlertJob.new
    assert job.send(:first_occurrence_in_deploy?, @issue.reload, release)
  end

  test "first_occurrence_in_deploy returns false for issues created before deploy" do
    release = Release.find_or_create_by!(
      account: @account,
      project: @project,
      version: "v#{SecureRandom.hex(4)}"
    ) do |r|
      r.deployed_at = 1.hour.ago
    end
    @issue.update!(first_seen_at: 2.hours.ago, closed_at: nil)

    job = IssueAlertJob.new
    refute job.send(:first_occurrence_in_deploy?, @issue.reload, release)
  end

  private

  def redis
    @redis ||= Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/1")
  end
end
