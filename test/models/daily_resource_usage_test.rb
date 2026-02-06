require "test_helper"

class DailyResourceUsageTest < ActiveSupport::TestCase
  # Associations

  test "belongs to account" do
    association = DailyResourceUsage.reflect_on_association(:account)
    assert_equal :belongs_to, association.macro
  end

  # Validations

  test "validates presence of day" do
    usage = DailyResourceUsage.new(account: accounts(:default), day: nil)
    refute usage.valid?
    assert_includes usage.errors[:day], "can't be blank"
  end

  test "validates uniqueness of day scoped to account" do
    # Use existing fixture
    existing = daily_resource_usages(:today)
    duplicate = DailyResourceUsage.new(account: existing.account, day: existing.day)
    refute duplicate.valid?
    assert duplicate.errors[:day].present?
  end

  # total_resources_used

  test "total_resources_used sums all resource counts" do
    usage = DailyResourceUsage.new(
      errors_count: 100,
      ai_summaries_count: 10,
      pull_requests_count: 5,
      uptime_monitors_count: 3,
      status_pages_count: 1
    )
    assert_equal 119, usage.total_resources_used
  end

  test "total_resources_used treats nil as zero" do
    usage = DailyResourceUsage.new(
      errors_count: nil,
      ai_summaries_count: 10,
      pull_requests_count: nil,
      uptime_monitors_count: 3,
      status_pages_count: nil
    )
    assert_equal 13, usage.total_resources_used
  end

  test "total_resources_used returns 0 when all nil" do
    usage = DailyResourceUsage.new(
      errors_count: nil,
      ai_summaries_count: nil,
      pull_requests_count: nil,
      uptime_monitors_count: nil,
      status_pages_count: nil
    )
    assert_equal 0, usage.total_resources_used
  end
end
