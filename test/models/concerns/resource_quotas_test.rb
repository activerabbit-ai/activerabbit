require "test_helper"

class ResourceQuotasTest < ActiveSupport::TestCase
  # ==========================================================================
  # PLAN_QUOTAS constant
  # ==========================================================================

  test "PLAN_QUOTAS defines quotas for all plans" do
    assert_equal %i[free trial team business].sort, ResourceQuotas::PLAN_QUOTAS.keys.sort
  end

  test "PLAN_QUOTAS includes all resource types for every plan" do
    expected_keys = %i[events ai_summaries pull_requests uptime_monitors status_pages projects]
    ResourceQuotas::PLAN_QUOTAS.each do |plan, quotas|
      expected_keys.each do |key|
        assert quotas.key?(key), "#{plan} plan is missing :#{key}"
      end
    end
  end

  test "PLAN_QUOTAS is frozen" do
    assert ResourceQuotas::PLAN_QUOTAS.frozen?
  end

  # ==========================================================================
  # event_quota_value
  # ==========================================================================

  test "event_quota_value returns 5000 for free plan" do
    account = Account.new(current_plan: "free")
    assert_equal 5_000, account.event_quota_value
  end

  test "event_quota_value returns 50000 for trial plan" do
    account = accounts(:trial_account)
    assert_equal 50_000, account.event_quota_value
  end

  test "event_quota_value returns 50000 for team plan" do
    account = accounts(:team_account)
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

  test "event_quota_value handles mixed-case plan names" do
    account = Account.new(current_plan: "Team")
    assert_equal 50_000, account.event_quota_value
  end

  # ==========================================================================
  # ai_summaries_quota
  # ==========================================================================

  test "ai_summaries_quota returns 0 for free plan" do
    account = Account.new(current_plan: "free")
    assert_equal 0, account.ai_summaries_quota
  end

  test "ai_summaries_quota returns 20 for trial plan" do
    account = accounts(:trial_account)
    assert_equal 20, account.ai_summaries_quota
  end

  test "ai_summaries_quota returns 20 for team plan" do
    account = accounts(:team_account)
    assert_equal 20, account.ai_summaries_quota
  end

  test "ai_summaries_quota returns 100 for business plan" do
    account = Account.new(current_plan: "business")
    assert_equal 100, account.ai_summaries_quota
  end

  # ==========================================================================
  # pull_requests_quota
  # ==========================================================================

  test "pull_requests_quota returns 0 for free plan" do
    account = Account.new(current_plan: "free")
    assert_equal 0, account.pull_requests_quota
  end

  test "pull_requests_quota returns 100 for trial plan" do
    account = accounts(:trial_account)
    assert_equal 100, account.pull_requests_quota
  end

  test "pull_requests_quota returns 20 for team plan" do
    account = accounts(:team_account)
    assert_equal 20, account.pull_requests_quota
  end

  test "pull_requests_quota returns 250 for business plan" do
    account = Account.new(current_plan: "business")
    assert_equal 250, account.pull_requests_quota
  end

  # ==========================================================================
  # uptime_monitors_quota
  # ==========================================================================

  test "uptime_monitors_quota returns 0 for free plan" do
    account = Account.new(current_plan: "free")
    assert_equal 0, account.uptime_monitors_quota
  end

  test "uptime_monitors_quota returns 20 for trial plan" do
    account = accounts(:trial_account)
    assert_equal 20, account.uptime_monitors_quota
  end

  test "uptime_monitors_quota returns 20 for team plan" do
    account = accounts(:team_account)
    assert_equal 20, account.uptime_monitors_quota
  end

  test "uptime_monitors_quota returns 5 for business plan" do
    account = Account.new(current_plan: "business")
    assert_equal 5, account.uptime_monitors_quota
  end

  # ==========================================================================
  # status_pages_quota
  # ==========================================================================

  test "status_pages_quota returns 0 for free plan" do
    account = Account.new(current_plan: "free")
    assert_equal 0, account.status_pages_quota
  end

  test "status_pages_quota returns 5 for trial plan" do
    account = accounts(:trial_account)
    assert_equal 5, account.status_pages_quota
  end

  test "status_pages_quota returns 5 for team plan" do
    account = accounts(:team_account)
    assert_equal 5, account.status_pages_quota
  end

  test "status_pages_quota returns 1 for business plan" do
    account = Account.new(current_plan: "business")
    assert_equal 1, account.status_pages_quota
  end

  # ==========================================================================
  # projects_quota
  # ==========================================================================

  test "projects_quota returns 999999 for free plan" do
    account = Account.new(current_plan: "free")
    assert_equal 999_999, account.projects_quota
  end

  test "projects_quota returns 10 for trial plan" do
    account = accounts(:trial_account)
    assert_equal 10, account.projects_quota
  end

  test "projects_quota returns 10 for team plan" do
    account = accounts(:team_account)
    assert_equal 10, account.projects_quota
  end

  test "projects_quota returns 50 for business plan" do
    account = Account.new(current_plan: "business")
    assert_equal 50, account.projects_quota
  end

  # ==========================================================================
  # effective_plan_name
  # ==========================================================================

  test "effective_plan_name returns Free Trial for trial account" do
    account = accounts(:trial_account)
    assert_equal "Free Trial", account.effective_plan_name
  end

  test "effective_plan_name returns Team for team plan" do
    account = accounts(:team_account)
    assert_equal "Team", account.effective_plan_name
  end

  test "effective_plan_name returns Free for free plan" do
    account = Account.new(current_plan: "free")
    assert_equal "Free", account.effective_plan_name
  end

  test "effective_plan_name returns Business for business plan" do
    account = Account.new(current_plan: "business")
    assert_equal "Business", account.effective_plan_name
  end

  # ==========================================================================
  # Usage tracking methods — nil cached values default to 0
  # ==========================================================================

  test "events_used_in_billing_period returns 0 when cached value is nil" do
    account = Account.new(current_plan: "free", cached_events_used: nil)
    assert_equal 0, account.events_used_in_billing_period
  end

  test "events_used_in_billing_period returns cached value when present" do
    account = accounts(:team_account)
    account.cached_events_used = 1_234
    assert_equal 1_234, account.events_used_in_billing_period
  end

  test "ai_summaries_used_in_period returns 0 when nil" do
    account = Account.new(current_plan: "free", cached_ai_summaries_used: nil)
    assert_equal 0, account.ai_summaries_used_in_period
  end

  test "ai_summaries_used_in_period returns cached value when present" do
    account = accounts(:team_account)
    account.cached_ai_summaries_used = 7
    assert_equal 7, account.ai_summaries_used_in_period
  end

  test "pull_requests_used_in_period returns 0 when nil" do
    account = Account.new(current_plan: "free", cached_pull_requests_used: nil)
    assert_equal 0, account.pull_requests_used_in_period
  end

  test "uptime_monitors_used returns 0 when nil" do
    account = Account.new(current_plan: "free", cached_uptime_monitors_used: nil)
    assert_equal 0, account.uptime_monitors_used
  end

  test "status_pages_used returns 0 when nil" do
    account = Account.new(current_plan: "free", cached_status_pages_used: nil)
    assert_equal 0, account.status_pages_used
  end

  test "projects_used returns 0 when nil" do
    account = Account.new(current_plan: "free", cached_projects_used: nil)
    assert_equal 0, account.projects_used
  end

  # ==========================================================================
  # usage_data_available?
  # ==========================================================================

  test "usage_data_available? returns false when usage_cached_at is nil" do
    account = Account.new(current_plan: "free", usage_cached_at: nil)
    assert_not account.usage_data_available?
  end

  test "usage_data_available? returns true when usage_cached_at is present" do
    account = accounts(:team_account)
    account.usage_cached_at = Time.current
    assert account.usage_data_available?
  end

  # ==========================================================================
  # within_quota? — boundary tests across resource types
  # ==========================================================================

  test "within_quota? returns true when under quota" do
    account = accounts(:team_account)
    account.cached_events_used = 10_000
    assert account.within_quota?(:events)
  end

  test "within_quota? returns false when at exact quota" do
    account = accounts(:team_account)
    account.cached_events_used = 50_000
    assert_not account.within_quota?(:events)
  end

  test "within_quota? returns false when over quota" do
    account = accounts(:team_account)
    account.cached_events_used = 60_000
    assert_not account.within_quota?(:events)
  end

  test "within_quota? returns true one below quota" do
    account = accounts(:team_account)
    account.cached_ai_summaries_used = 19 # team quota is 20
    assert account.within_quota?(:ai_summaries)
  end

  test "within_quota? returns false at quota boundary for ai_summaries" do
    account = accounts(:team_account)
    account.cached_ai_summaries_used = 20
    assert_not account.within_quota?(:ai_summaries)
  end

  test "within_quota? returns false for unknown resource type" do
    account = accounts(:team_account)
    assert_not account.within_quota?(:nonexistent)
  end

  test "within_quota? works for pull_requests" do
    account = accounts(:team_account)
    account.cached_pull_requests_used = 5
    assert account.within_quota?(:pull_requests)
  end

  test "within_quota? for uptime_monitors on free plan is always false" do
    account = Account.new(current_plan: "free", cached_uptime_monitors_used: 0)
    # Free plan has 0 uptime_monitors quota, so 0 < 0 is false
    assert_not account.within_quota?(:uptime_monitors)
  end

  test "within_quota? for uptime_monitors on team plan with usage" do
    account = accounts(:team_account)
    account.cached_uptime_monitors_used = 15
    assert account.within_quota?(:uptime_monitors) # 15 < 20
  end

  test "within_quota? for status_pages on free plan is always false" do
    account = Account.new(current_plan: "free", cached_status_pages_used: 0)
    assert_not account.within_quota?(:status_pages)
  end

  test "within_quota? for projects on free plan" do
    account = Account.new(current_plan: "free", cached_projects_used: 0)
    assert account.within_quota?(:projects) # 0 < 999999
  end

  test "within_quota? for projects at 1 on free plan (unlimited)" do
    account = Account.new(current_plan: "free", cached_projects_used: 1)
    assert account.within_quota?(:projects) # 1 < 999999 => true (unlimited)
  end

  # ==========================================================================
  # AI Generate quota per plan (integration-style tests)
  # ==========================================================================

  test "free plan gets 0 AI summaries" do
    account = accounts(:free_account)
    account.current_plan = "free"
    account.trial_ends_at = 1.day.ago
    account.cached_ai_summaries_used = 0

    assert_equal 0, account.ai_summaries_quota
    assert_not account.within_quota?(:ai_summaries) # 0 < 0 => false (not available)
  end

  test "free plan with any used is over AI quota" do
    account = accounts(:free_account)
    account.current_plan = "free"
    account.trial_ends_at = 1.day.ago
    account.cached_ai_summaries_used = 1

    assert_not account.within_quota?(:ai_summaries)
  end

  test "trial account gets 20 AI summaries" do
    account = accounts(:trial_account)
    account.cached_ai_summaries_used = 0

    assert_equal 20, account.ai_summaries_quota
    assert account.within_quota?(:ai_summaries)
  end

  test "trial account with 5 used is within AI quota" do
    account = accounts(:trial_account)
    account.cached_ai_summaries_used = 5

    assert_equal 20, account.ai_summaries_quota
    assert account.within_quota?(:ai_summaries)
  end

  test "trial account with 20 used is over AI quota" do
    account = accounts(:trial_account)
    account.cached_ai_summaries_used = 20

    assert_equal 20, account.ai_summaries_quota
    assert_not account.within_quota?(:ai_summaries)
  end

  test "team plan gets 20 AI summaries" do
    account = accounts(:team_account)
    account.cached_ai_summaries_used = 0

    assert_equal 20, account.ai_summaries_quota
    assert account.within_quota?(:ai_summaries)
  end

  test "team plan with 19 used is still within AI quota" do
    account = accounts(:team_account)
    account.cached_ai_summaries_used = 19

    assert account.within_quota?(:ai_summaries),
      "Team plan with 19/20 used should still be within quota"
  end

  test "team plan with 20 used is over AI quota" do
    account = accounts(:team_account)
    account.cached_ai_summaries_used = 20

    assert_not account.within_quota?(:ai_summaries),
      "Team plan with 20/20 used should be over quota"
  end

  test "business plan gets 100 AI summaries" do
    account = accounts(:other_account)
    account.current_plan = "business"
    account.cached_ai_summaries_used = 0

    assert_equal 100, account.ai_summaries_quota
    assert account.within_quota?(:ai_summaries)
  end

  test "business plan with 100 used is over AI quota" do
    account = accounts(:other_account)
    account.current_plan = "business"
    account.cached_ai_summaries_used = 100

    assert_not account.within_quota?(:ai_summaries),
      "Business plan with 100/100 used should be over quota"
  end

  # ==========================================================================
  # usage_percentage
  # ==========================================================================

  test "usage_percentage returns correct percentage when under quota" do
    account = accounts(:team_account)
    account.cached_events_used = 25_000

    assert_equal 50.0, account.usage_percentage(:events)
  end

  test "usage_percentage returns 0.0 when no usage" do
    account = accounts(:team_account)
    account.cached_pull_requests_used = 0

    assert_equal 0.0, account.usage_percentage(:pull_requests)
  end

  test "usage_percentage returns 100.0 at exact quota" do
    account = accounts(:team_account)
    account.cached_events_used = 50_000

    assert_equal 100.0, account.usage_percentage(:events)
  end

  test "usage_percentage can exceed 100" do
    account = accounts(:team_account)
    account.cached_events_used = 75_000

    assert_equal 150.0, account.usage_percentage(:events)
  end

  test "usage_percentage returns 0.0 when quota is zero" do
    account = Account.new(current_plan: "free", cached_uptime_monitors_used: 5)
    # Free plan has 0 uptime_monitors quota
    assert_equal 0.0, account.usage_percentage(:uptime_monitors)
  end

  test "usage_percentage returns 0.0 for unknown resource type" do
    account = accounts(:team_account)
    assert_equal 0.0, account.usage_percentage(:nonexistent)
  end

  test "usage_percentage rounds to two decimal places" do
    account = accounts(:team_account)
    account.cached_ai_summaries_used = 7 # 7/20 = 35.0

    assert_equal 35.0, account.usage_percentage(:ai_summaries)
  end

  # ==========================================================================
  # usage_summary
  # ==========================================================================

  test "usage_summary returns hash with all resource types" do
    account = accounts(:team_account)
    account.cached_events_used = 10_000
    account.cached_ai_summaries_used = 5
    account.cached_pull_requests_used = 3
    account.cached_uptime_monitors_used = 2
    account.cached_status_pages_used = 1
    account.cached_projects_used = 4

    summary = account.usage_summary

    assert_equal %i[events ai_summaries pull_requests uptime_monitors status_pages projects].sort,
                 summary.keys.sort
  end

  test "usage_summary includes correct quotas for team plan" do
    account = accounts(:team_account)

    summary = account.usage_summary

    assert_equal 50_000, summary[:events][:quota]
    assert_equal 20, summary[:ai_summaries][:quota]
    assert_equal 20, summary[:pull_requests][:quota]
    assert_equal 20, summary[:uptime_monitors][:quota]
    assert_equal 5, summary[:status_pages][:quota]
    assert_equal 10, summary[:projects][:quota]
  end

  test "usage_summary includes used counts" do
    account = accounts(:team_account)
    account.cached_events_used = 10_000
    account.cached_ai_summaries_used = 5
    account.cached_pull_requests_used = 3

    summary = account.usage_summary

    assert_equal 10_000, summary[:events][:used]
    assert_equal 5, summary[:ai_summaries][:used]
    assert_equal 3, summary[:pull_requests][:used]
  end

  test "usage_summary calculates remaining correctly" do
    account = accounts(:team_account)
    account.cached_events_used = 10_000
    account.cached_ai_summaries_used = 5

    summary = account.usage_summary

    assert_equal 40_000, summary[:events][:remaining]
    assert_equal 15, summary[:ai_summaries][:remaining]
  end

  test "usage_summary remaining is clamped to 0 when over quota" do
    account = accounts(:team_account)
    account.cached_events_used = 60_000

    summary = account.usage_summary

    assert_equal 0, summary[:events][:remaining]
  end

  test "usage_summary includes percentage" do
    account = accounts(:team_account)
    account.cached_events_used = 10_000

    summary = account.usage_summary

    assert_equal 20.0, summary[:events][:percentage]
  end

  test "usage_summary includes within_quota flag" do
    account = accounts(:team_account)
    account.cached_events_used = 10_000
    account.cached_ai_summaries_used = 25

    summary = account.usage_summary

    assert summary[:events][:within_quota]
    assert_not summary[:ai_summaries][:within_quota] # 25 >= 20
  end

  test "usage_summary is memoized within the same instance" do
    account = accounts(:team_account)
    account.cached_events_used = 10_000

    summary1 = account.usage_summary
    account.cached_events_used = 20_000
    summary2 = account.usage_summary

    # Should be the same object (memoized)
    assert_same summary1, summary2
    assert_equal 10_000, summary2[:events][:used]
  end

  # ==========================================================================
  # effective_plan_key (private, tested via send)
  # ==========================================================================

  test "effective_plan_key returns :trial when on_trial? is true" do
    account = accounts(:trial_account)
    assert_equal :trial, account.send(:effective_plan_key)
  end

  test "effective_plan_key returns :free when trial expired without payment" do
    account = accounts(:free_account)
    account.current_plan = "team"
    account.trial_ends_at = 1.day.ago

    assert_equal :free, account.send(:effective_plan_key)
  end

  test "effective_plan_key returns normalized plan key for non-trial accounts" do
    account = accounts(:team_account)
    assert_equal :team, account.send(:effective_plan_key)
  end

  test "effective_plan_key returns :business for business plan" do
    account = Account.new(current_plan: "business")
    assert_equal :business, account.send(:effective_plan_key)
  end

  # ==========================================================================
  # normalized_plan_key (private)
  # ==========================================================================

  test "normalized_plan_key downcases and strips plan name" do
    account = Account.new(current_plan: "  TEAM  ")
    assert_equal :team, account.send(:normalized_plan_key)
  end

  test "normalized_plan_key defaults to :free for unknown plan" do
    account = Account.new(current_plan: "enterprise")
    assert_equal :free, account.send(:normalized_plan_key)
  end

  test "normalized_plan_key defaults to :free for empty string" do
    account = Account.new(current_plan: "")
    assert_equal :free, account.send(:normalized_plan_key)
  end

  # ==========================================================================
  # billing period helpers (private)
  # ==========================================================================

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
