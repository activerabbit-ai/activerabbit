require "test_helper"

class OverageCalculatorTest < ActiveSupport::TestCase
  test "computes overage above quota" do
    account = accounts(:default)
    account.update!(current_plan: "developer")

    # Update or create a daily count exceeding quota
    daily_count = DailyEventCount.find_or_initialize_by(account_id: account.id, day: Date.current)
    daily_count.count = 60_000
    daily_count.save!

    calc = OverageCalculator.new(account: account)
    start_time = Time.current.beginning_of_month
    end_time = Time.current.end_of_month

    overage = calc.overage_events(period_start: start_time, period_end: end_time)
    assert overage >= 10_000
  end
end
