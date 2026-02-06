require "test_helper"

class ResourceQuotasTest < ActiveSupport::TestCase
  # PLAN_QUOTAS constant

  test "PLAN_QUOTAS defines quotas for all plans" do
    assert_includes ResourceQuotas::PLAN_QUOTAS.keys, :free
    assert_includes ResourceQuotas::PLAN_QUOTAS.keys, :team
    assert_includes ResourceQuotas::PLAN_QUOTAS.keys, :business
  end

  test "PLAN_QUOTAS includes all resource types" do
    ResourceQuotas::PLAN_QUOTAS.each do |_plan, quotas|
      assert_includes quotas.keys, :events
      assert_includes quotas.keys, :ai_summaries
      assert_includes quotas.keys, :pull_requests
      assert_includes quotas.keys, :uptime_monitors
      assert_includes quotas.keys, :status_pages
    end
  end

  # event_quota_value

  test "event_quota_value returns 5000 for free plan" do
    account = accounts(:free_account)
    account.current_plan = "free"
    assert_equal 5_000, account.event_quota_value
  end

  test "event_quota_value returns 50000 for team plan" do
    account = accounts(:team_account)
    account.current_plan = "team"
    assert_equal 50_000, account.event_quota_value
  end

  test "event_quota_value returns 100000 for business plan" do
    account = Account.new(current_plan: "business")
    assert_equal 100_000, account.event_quota_value
  end

  test "event_quota_value defaults to free plan quota for unknown plan" do
    account = Account.new(current_plan: "unknown")
    assert_equal 5_000, account.event_quota_value
  end

  test "event_quota_value handles uppercase plan names" do
    account = accounts(:default)
    account.current_plan = "TEAM"
    assert_equal 50_000, account.event_quota_value
  end

  # ai_summaries_quota

  test "ai_summaries_quota returns correct values for free plan" do
    account = Account.new(current_plan: "free")
    assert_equal 5, account.ai_summaries_quota
  end

  test "ai_summaries_quota returns correct values for team plan" do
    account = Account.new(current_plan: "team")
    assert_equal 300, account.ai_summaries_quota
  end

  test "ai_summaries_quota returns correct values for business plan" do
    account = Account.new(current_plan: "business")
    assert_equal 500, account.ai_summaries_quota
  end

  # pull_requests_quota

  test "pull_requests_quota returns correct values for free plan" do
    account = Account.new(current_plan: "free")
    assert_equal 5, account.pull_requests_quota
  end

  test "pull_requests_quota returns correct values for team plan" do
    account = Account.new(current_plan: "team")
    assert_equal 100, account.pull_requests_quota
  end

  test "pull_requests_quota returns correct values for business plan" do
    account = Account.new(current_plan: "business")
    assert_equal 250, account.pull_requests_quota
  end

  # usage_summary

  test "usage_summary returns hash with all resource types" do
    account = accounts(:team_account)
    account.current_plan = "team"
    account.cached_events_used = 10_000
    account.cached_ai_summaries_used = 25
    account.cached_pull_requests_used = 3
    account.cached_uptime_monitors_used = 2
    account.cached_status_pages_used = 1
    account.cached_projects_used = 5

    summary = account.usage_summary

    assert_equal [:events, :ai_summaries, :pull_requests, :uptime_monitors, :status_pages, :projects].sort,
                 summary.keys.sort
  end

  test "usage_summary includes quota for each resource" do
    account = accounts(:team_account)
    account.current_plan = "team"

    summary = account.usage_summary

    assert_equal 50_000, summary[:events][:quota]
    assert_equal 300, summary[:ai_summaries][:quota]
    assert_equal 100, summary[:pull_requests][:quota]
  end

  # billing period helpers

  test "billing period defaults to current month when not set" do
    account = accounts(:default)
    account.event_usage_period_start = nil
    account.event_usage_period_end = nil

    assert_equal Time.current.beginning_of_month, account.send(:billing_period_start)
    assert_equal Time.current.end_of_month, account.send(:billing_period_end)
  end

  test "billing period uses set values when available" do
    account = accounts(:default)
    start_date = Time.zone.parse("2024-01-01")
    end_date = Time.zone.parse("2024-01-31")
    account.event_usage_period_start = start_date
    account.event_usage_period_end = end_date

    assert_equal start_date, account.send(:billing_period_start)
    assert_equal end_date, account.send(:billing_period_end)
  end
end
