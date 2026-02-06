require "test_helper"

class AccountTest < ActiveSupport::TestCase
  # Validations

  test "validates presence of name" do
    account = Account.new(name: nil)
    refute account.valid?
    assert_includes account.errors[:name], "can't be blank"
  end

  # has_any_stats?

  test "has_any_stats returns false when usage_cached_at is nil" do
    account = accounts(:default)
    account.usage_cached_at = nil
    refute account.has_any_stats?
  end

  test "has_any_stats returns true when account has events" do
    account = accounts(:team_account)
    account.update!(
      cached_events_used: 100,
      cached_performance_events_used: 0,
      cached_ai_summaries_used: 0,
      cached_pull_requests_used: 0,
      usage_cached_at: Time.current
    )
    assert account.has_any_stats?
  end

  test "has_any_stats returns true when account has performance events" do
    account = accounts(:default)
    account.update!(
      cached_events_used: 0,
      cached_performance_events_used: 50,
      cached_ai_summaries_used: 0,
      cached_pull_requests_used: 0,
      usage_cached_at: Time.current
    )
    assert account.has_any_stats?
  end

  test "has_any_stats returns true when account has AI summaries" do
    account = accounts(:default)
    account.update!(
      cached_events_used: 0,
      cached_performance_events_used: 0,
      cached_ai_summaries_used: 5,
      cached_pull_requests_used: 0,
      usage_cached_at: Time.current
    )
    assert account.has_any_stats?
  end

  test "has_any_stats returns true when account has pull requests" do
    account = accounts(:default)
    account.update!(
      cached_events_used: 0,
      cached_performance_events_used: 0,
      cached_ai_summaries_used: 0,
      cached_pull_requests_used: 3,
      usage_cached_at: Time.current
    )
    assert account.has_any_stats?
  end

  test "has_any_stats returns false when account has zero stats" do
    account = accounts(:default)
    account.update!(
      cached_events_used: 0,
      cached_performance_events_used: 0,
      cached_ai_summaries_used: 0,
      cached_pull_requests_used: 0,
      usage_cached_at: Time.current
    )
    refute account.has_any_stats?
  end
end
