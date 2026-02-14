# frozen_string_literal: true

require "test_helper"

class ResourceQuotasTest < ActiveSupport::TestCase
  # ===========================================================================
  # Free plan quota values
  # ===========================================================================

  test "free plan has 5000 event quota" do
    assert_equal 5_000, ResourceQuotas::PLAN_QUOTAS[:free][:events]
  end

  test "free plan has 0 AI summaries" do
    assert_equal 0, ResourceQuotas::PLAN_QUOTAS[:free][:ai_summaries]
  end

  test "free plan has 0 pull requests" do
    assert_equal 0, ResourceQuotas::PLAN_QUOTAS[:free][:pull_requests]
  end

  test "free plan has unlimited projects" do
    assert_equal 999_999, ResourceQuotas::PLAN_QUOTAS[:free][:projects]
  end

  test "free plan has 1 user" do
    assert_equal 1, ResourceQuotas::PLAN_QUOTAS[:free][:users]
  end

  test "free plan has 5 days data retention" do
    assert_equal 5, ResourceQuotas::PLAN_QUOTAS[:free][:data_retention_days]
  end

  test "free plan has no slack notifications" do
    assert_equal false, ResourceQuotas::PLAN_QUOTAS[:free][:slack_notifications]
  end

  test "free plan has 0 uptime monitors" do
    assert_equal 0, ResourceQuotas::PLAN_QUOTAS[:free][:uptime_monitors]
  end

  test "free plan has 0 status pages" do
    assert_equal 0, ResourceQuotas::PLAN_QUOTAS[:free][:status_pages]
  end

  # ===========================================================================
  # Team plan quota values
  # ===========================================================================

  test "team plan has 50000 event quota" do
    assert_equal 50_000, ResourceQuotas::PLAN_QUOTAS[:team][:events]
  end

  test "team plan has 20 AI summaries" do
    assert_equal 20, ResourceQuotas::PLAN_QUOTAS[:team][:ai_summaries]
  end

  test "team plan has 20 pull requests" do
    assert_equal 20, ResourceQuotas::PLAN_QUOTAS[:team][:pull_requests]
  end

  test "team plan has slack notifications" do
    assert_equal true, ResourceQuotas::PLAN_QUOTAS[:team][:slack_notifications]
  end

  test "team plan has 31 days data retention" do
    assert_equal 31, ResourceQuotas::PLAN_QUOTAS[:team][:data_retention_days]
  end

  # ===========================================================================
  # Business plan quota values
  # ===========================================================================

  test "business plan has 100000 event quota" do
    assert_equal 100_000, ResourceQuotas::PLAN_QUOTAS[:business][:events]
  end

  test "business plan has 100 AI summaries" do
    assert_equal 100, ResourceQuotas::PLAN_QUOTAS[:business][:ai_summaries]
  end

  test "business plan has 250 pull requests" do
    assert_equal 250, ResourceQuotas::PLAN_QUOTAS[:business][:pull_requests]
  end

  # ===========================================================================
  # Helper method tests (on Account model)
  # ===========================================================================

  test "on_free_plan? returns true for free plan account" do
    account = accounts(:free_account)
    assert account.on_free_plan?, "Free account should be on free plan"
  end

  test "on_free_plan? returns false for team plan account" do
    account = accounts(:team_account)
    refute account.on_free_plan?, "Team account should not be on free plan"
  end

  test "on_free_plan? returns false for trial account" do
    account = accounts(:default) # team plan with active trial
    refute account.on_free_plan?, "Trial account should not be on free plan"
  end

  test "slack_notifications_allowed? returns false for free plan" do
    account = accounts(:free_account)
    refute account.slack_notifications_allowed?,
      "Free plan should not allow Slack notifications"
  end

  test "slack_notifications_allowed? returns true for team plan" do
    account = accounts(:team_account)
    assert account.slack_notifications_allowed?,
      "Team plan should allow Slack notifications"
  end

  test "slack_notifications_allowed? returns true for business plan" do
    account = accounts(:other_account) # business plan
    assert account.slack_notifications_allowed?,
      "Business plan should allow Slack notifications"
  end

  test "data_retention_days returns 5 for free plan" do
    account = accounts(:free_account)
    assert_equal 5, account.data_retention_days
  end

  test "data_retention_days returns 31 for team plan" do
    account = accounts(:team_account)
    assert_equal 31, account.data_retention_days
  end

  test "data_retention_cutoff returns 5 days ago for free plan" do
    account = accounts(:free_account)
    assert_in_delta 5.days.ago, account.data_retention_cutoff, 5.seconds
  end

  test "data_retention_cutoff returns 31 days ago for team plan" do
    account = accounts(:team_account)
    assert_in_delta 31.days.ago, account.data_retention_cutoff, 5.seconds
  end

  # ===========================================================================
  # free_plan_events_capped? tests
  # ===========================================================================

  test "free_plan_events_capped? returns true when free plan exceeds event quota" do
    account = accounts(:free_account)
    account.update!(cached_events_used: 5_001)

    assert account.free_plan_events_capped?,
      "Should be capped when events exceed 5,000 on free plan"
  end

  test "free_plan_events_capped? returns true when free plan equals event quota" do
    account = accounts(:free_account)
    account.update!(cached_events_used: 5_000)

    assert account.free_plan_events_capped?,
      "Should be capped when events equal 5,000 on free plan (within_quota? uses <, not <=)"
  end

  test "free_plan_events_capped? returns false when free plan is under quota" do
    account = accounts(:free_account)
    account.update!(cached_events_used: 4_999)

    refute account.free_plan_events_capped?,
      "Should not be capped when events are under 5,000 on free plan"
  end

  test "free_plan_events_capped? returns false for team plan even when over quota" do
    account = accounts(:team_account)
    account.update!(cached_events_used: 999_999)

    refute account.free_plan_events_capped?,
      "Team plan should never be hard-capped (uses overage billing instead)"
  end

  test "free_plan_events_capped? returns false for trial account" do
    account = accounts(:default) # trial
    account.update!(cached_events_used: 999_999)

    refute account.free_plan_events_capped?,
      "Trial account should not be hard-capped"
  end

  # ===========================================================================
  # within_quota? tests
  # ===========================================================================

  test "within_quota? returns false for AI summaries on free plan" do
    account = accounts(:free_account)
    account.update!(cached_ai_summaries_used: 0)

    refute account.within_quota?(:ai_summaries),
      "Free plan has 0 AI summaries quota, so 0 < 0 is false"
  end

  test "within_quota? returns true for events on free plan under limit" do
    account = accounts(:free_account)
    account.update!(cached_events_used: 100)

    assert account.within_quota?(:events),
      "Free plan should be within quota when under 5,000 events"
  end

  test "within_quota? returns false for events on free plan at limit" do
    account = accounts(:free_account)
    account.update!(cached_events_used: 5_000)

    refute account.within_quota?(:events),
      "Free plan should be over quota when at 5,000 events"
  end

  # ===========================================================================
  # usage_percentage tests
  # ===========================================================================

  test "usage_percentage returns correct value for free plan events" do
    account = accounts(:free_account)
    account.update!(cached_events_used: 2_500)

    assert_equal 50.0, account.usage_percentage(:events)
  end

  test "usage_percentage returns over 100 when exceeding quota" do
    account = accounts(:free_account)
    account.update!(cached_events_used: 6_000)

    assert_equal 120.0, account.usage_percentage(:events)
  end

  # ===========================================================================
  # effective_plan_key tests
  # ===========================================================================

  test "effective_plan_key returns :trial for account with active trial" do
    account = accounts(:default) # trial_ends_at = 7.days.from_now
    assert_equal :trial, account.send(:effective_plan_key)
  end

  test "effective_plan_key returns :free for free plan account" do
    account = accounts(:free_account)
    assert_equal :free, account.send(:effective_plan_key)
  end

  test "effective_plan_key returns :team for team plan account without trial" do
    account = accounts(:team_account)
    assert_equal :team, account.send(:effective_plan_key)
  end

  test "effective_plan_key returns :business for business plan account" do
    account = accounts(:other_account) # business plan
    assert_equal :business, account.send(:effective_plan_key)
  end
end
