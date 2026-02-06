require "test_helper"

class UsageReporterTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @reporter = UsageReporter.new(account: @account)
  end

  test "report_daily! does nothing when no subscription item" do
    @account.update!(overage_subscription_item_id: nil)

    # Should not raise and should return early
    assert_nothing_raised do
      @reporter.report_daily!
    end
  end

  test "report_daily! reports to Stripe when subscription item present" do
    @account.update!(overage_subscription_item_id: "si_test123")

    # Create some usage data
    DailyEventCount.find_or_initialize_by(account_id: @account.id, day: Date.current).tap do |rec|
      rec.count = 150_000 # Should report 2 units (150k / 100k = 1.5, ceil = 2)
      rec.save!
    end

    stripe_called = false

    # Use define_singleton_method to create the stub
    Stripe::UsageRecord.define_singleton_method(:create) do |**args|
      stripe_called = true
      OpenStruct.new(id: "usage_123")
    end

    begin
      @reporter.report_daily!
      assert stripe_called
    ensure
      # Remove the stub
      Stripe::UsageRecord.singleton_class.remove_method(:create) rescue nil
    end
  end

  test "report_daily! does not report when count is zero" do
    @account.update!(overage_subscription_item_id: "si_test123")

    # Create zero usage data
    DailyEventCount.find_or_initialize_by(account_id: @account.id, day: Date.current).tap do |rec|
      rec.count = 0
      rec.save!
    end

    stripe_called = false

    Stripe::UsageRecord.define_singleton_method(:create) do |**args|
      stripe_called = true
      OpenStruct.new(id: "usage_123")
    end

    begin
      @reporter.report_daily!
      refute stripe_called
    ensure
      Stripe::UsageRecord.singleton_class.remove_method(:create) rescue nil
    end
  end
end
