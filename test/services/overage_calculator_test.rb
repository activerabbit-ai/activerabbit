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

  # ===========================================================================
  # Free plan: no overage fees
  # ===========================================================================

  test "attach_overage_invoice_item! skips free plan accounts" do
    free_account = accounts(:free_account)

    # Even with usage over quota, free plan should not create overage invoice items
    daily_count = DailyEventCount.find_or_initialize_by(account_id: free_account.id, day: Date.current)
    daily_count.count = 10_000
    daily_count.save!

    calc = OverageCalculator.new(account: free_account)

    stripe_invoice = {
      "id" => "in_test_free",
      "period_start" => Time.current.beginning_of_month.to_i,
      "period_end" => Time.current.end_of_month.to_i
    }

    # Should return early without calling Stripe::InvoiceItem.create
    Stripe::InvoiceItem.stub(:create, ->(**args) {
      raise "Should NOT create overage invoice item for free plan!"
    }) do
      assert_nothing_raised do
        calc.attach_overage_invoice_item!(
          stripe_invoice: stripe_invoice,
          customer_id: "cus_test_free"
        )
      end
    end
  end

  test "attach_overage_invoice_item! processes team plan overages normally" do
    team_account = accounts(:team_account)

    daily_count = DailyEventCount.find_or_initialize_by(account_id: team_account.id, day: Date.current)
    daily_count.count = 200_000  # Way over team quota
    daily_count.save!

    calc = OverageCalculator.new(account: team_account)

    stripe_invoice = {
      "id" => "in_test_team",
      "period_start" => Time.current.beginning_of_month.to_i,
      "period_end" => Time.current.end_of_month.to_i
    }

    # Stub Stripe to verify it IS called for team plan
    invoice_item_created = false
    Stripe::InvoiceItem.stub(:create, ->(**args) {
      invoice_item_created = true
      OpenStruct.new(id: "ii_test")
    }) do
      calc.attach_overage_invoice_item!(
        stripe_invoice: stripe_invoice,
        customer_id: "cus_test_team"
      )
    end

    assert invoice_item_created,
      "Team plan with overage should create Stripe invoice item"
  end
end
