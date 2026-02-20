# frozen_string_literal: true

require "test_helper"

# =============================================================================
# Plan Page, Usage Page, Billing Banner & Sidebar Messaging Tests
# =============================================================================
#
# Verifies that the correct copy and CTAs appear for each account state:
#   - Trial active (no subscription)
#   - Trial expired (no subscription)
#   - Free plan
#   - Team plan with active subscription
#   - Business plan with active subscription
#
class PlanPageMessagingTest < ActionDispatch::IntegrationTest

  # ---------------------------------------------------------------------------
  # Plan page button states
  # ---------------------------------------------------------------------------

  test "plan page shows Choose buttons for trial user (no Current Plan button)" do
    user = users(:trial_user)
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 7.days.from_now)
    sign_in user

    get plan_path
    assert_response :success

    assert_includes response.body, "Choose Free"
    assert_includes response.body, "Choose Team"
    assert_includes response.body, "Choose Business"
    assert_select "button[disabled]", { count: 0, text: "Current Plan" }
  end

  test "plan page shows Current Plan on Free button for free user" do
    user = users(:free_account_owner)
    account = accounts(:free_account)
    account.update!(current_plan: "free", trial_ends_at: 30.days.ago)
    sign_in user

    get plan_path
    assert_response :success

    assert_match(/Current Plan/, response.body)
    assert_includes response.body, "Choose Team"
    assert_includes response.body, "Choose Business"
  end

  test "plan page shows Current Plan on Team button for paying team user" do
    user = users(:second_owner)
    account = accounts(:team_account)
    account.update!(current_plan: "team", trial_ends_at: nil)

    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_plan_test_team_#{SecureRandom.hex(4)}" }
    Pay::Subscription.create!(
      customer: pay_customer,
      processor_id: "sub_plan_test_team_#{SecureRandom.hex(4)}",
      name: "default",
      processor_plan: "price_test",
      status: "active",
      quantity: 1
    )

    sign_in user

    get plan_path
    assert_response :success

    assert_select "button[disabled]", text: "Current Plan"
  end

  test "plan page shows Current Plan on Business button for paying business user" do
    user = users(:other_account_owner)
    account = accounts(:other_account)
    account.update!(current_plan: "business", trial_ends_at: nil)

    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_plan_test_biz_#{SecureRandom.hex(4)}" }
    Pay::Subscription.create!(
      customer: pay_customer,
      processor_id: "sub_plan_test_biz_#{SecureRandom.hex(4)}",
      name: "default",
      processor_plan: "price_biz_test",
      status: "active",
      quantity: 1
    )

    sign_in user

    get plan_path
    assert_response :success

    assert_select "button[disabled]", text: "Current Plan"
  end

  test "plan page shows trial info with subscribe CTA for trial user" do
    user = users(:trial_user)
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 10.days.from_now)
    sign_in user

    get plan_path
    assert_response :success

    assert_includes response.body, "14-day free trial"
    assert_includes response.body, "Subscribe to a plan to keep monitoring"
    assert_includes response.body, "remaining"
  end

  # ---------------------------------------------------------------------------
  # Plan page header messaging (rendered inline, not via billing banner)
  # ---------------------------------------------------------------------------

  test "plan page header shows subscribe CTA for active trial" do
    user = users(:trial_user)
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 10.days.from_now)
    sign_in user

    get plan_path
    assert_response :success

    assert_includes response.body, "Subscribe to a plan"
    assert_includes response.body, "monitoring uninterrupted"
    assert_includes response.body, "Free Trial"
  end

  test "plan page header not shown for paying team user" do
    user = users(:second_owner)
    account = accounts(:team_account)
    account.update!(current_plan: "team", trial_ends_at: nil)

    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_banner_test_team_#{SecureRandom.hex(4)}" }
    Pay::Subscription.create!(
      customer: pay_customer,
      processor_id: "sub_banner_test_team_#{SecureRandom.hex(4)}",
      name: "default",
      processor_plan: "price_test",
      status: "active",
      quantity: 1
    )

    sign_in user

    get plan_path
    assert_response :success

    refute_includes response.body, "Subscribe to a plan to keep"
    refute_includes response.body, "trial ended"
  end

  # ---------------------------------------------------------------------------
  # Usage page messaging
  # ---------------------------------------------------------------------------

  test "usage page shows subscribe CTA for active trial" do
    user = users(:trial_user)
    account = accounts(:trial_account)
    account.update!(
      current_plan: "trial",
      trial_ends_at: 10.days.from_now,
      cached_events_used: 100,
      cached_ai_summaries_used: 2,
      cached_pull_requests_used: 1,
      usage_cached_at: Time.current
    )
    sign_in user

    get usage_path
    assert_response :success

    assert_includes response.body, "Free Trial"
    assert_includes response.body, "days left"
    assert_includes response.body, "Choose Plan"
    refute_includes response.body, "Add Payment Method"
  end

  test "usage page shows Choose Plan link to plan page not billing portal" do
    user = users(:trial_user)
    account = accounts(:trial_account)
    account.update!(
      current_plan: "trial",
      trial_ends_at: 10.days.from_now,
      cached_events_used: 0,
      cached_ai_summaries_used: 0,
      cached_pull_requests_used: 0,
      usage_cached_at: Time.current
    )
    sign_in user

    get usage_path
    assert_response :success

    assert_select "a[href=?]", plan_path, text: "Choose Plan"
  end

  test "usage page shows expired trial with upgrade CTA" do
    user = users(:trial_user)
    account = accounts(:trial_account)
    account.update!(
      current_plan: "trial",
      trial_ends_at: 2.days.ago,
      cached_events_used: 0,
      cached_ai_summaries_used: 0,
      cached_pull_requests_used: 0,
      usage_cached_at: Time.current
    )

    orig_sub = Account.instance_method(:active_subscription?)
    orig_pay = Account.instance_method(:has_payment_method?)
    Account.define_method(:active_subscription?) { false }
    Account.define_method(:has_payment_method?) { false }

    begin
      sign_in user
      get usage_path
      assert_response :success

      assert_includes response.body, "trial ended"
      assert_includes response.body, "Choose a plan"
    ensure
      Account.define_method(:active_subscription?, orig_sub)
      Account.define_method(:has_payment_method?, orig_pay)
    end
  end

  # ---------------------------------------------------------------------------
  # Sidebar trial box messaging
  # ---------------------------------------------------------------------------

  test "sidebar shows Choose Plan CTA for active trial" do
    user = users(:trial_user)
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 10.days.from_now)
    sign_in user

    get plan_path
    assert_response :success

    assert_includes response.body, "Subscribe to a plan to keep monitoring"
    assert_select "a[href=?]", plan_path, text: "Choose Plan"
  end

  test "sidebar shows upgrade CTA for expired trial" do
    user = users(:trial_user)
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 2.days.ago)

    orig_sub = Account.instance_method(:active_subscription?)
    orig_pay = Account.instance_method(:has_payment_method?)
    Account.define_method(:active_subscription?) { false }
    Account.define_method(:has_payment_method?) { false }

    begin
      sign_in user
      get plan_path
      assert_response :success

      assert_includes response.body, "Trial expired"
      assert_includes response.body, "Upgrade"
    ensure
      Account.define_method(:active_subscription?, orig_sub)
      Account.define_method(:has_payment_method?, orig_pay)
    end
  end

  test "sidebar shows free plan box for free user" do
    user = users(:free_account_owner)
    account = accounts(:free_account)
    account.update!(current_plan: "free", trial_ends_at: 30.days.ago)
    sign_in user

    get plan_path
    assert_response :success

    assert_includes response.body, "Free plan"
    assert_includes response.body, "Upgrade"
  end

  test "sidebar does not show trial box for paying team user" do
    user = users(:second_owner)
    account = accounts(:team_account)
    account.update!(current_plan: "team", trial_ends_at: nil)

    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_sidebar_test_team_#{SecureRandom.hex(4)}" }
    Pay::Subscription.create!(
      customer: pay_customer,
      processor_id: "sub_sidebar_test_team_#{SecureRandom.hex(4)}",
      name: "default",
      processor_plan: "price_test",
      status: "active",
      quantity: 1
    )

    sign_in user

    get plan_path
    assert_response :success

    refute_includes response.body, "Subscribe to a plan to keep monitoring"
    refute_includes response.body, "Trial expired"
  end

  # ---------------------------------------------------------------------------
  # No "billing portal" links for trial/non-paying users
  # ---------------------------------------------------------------------------

  test "no billing portal button on usage page for trial user" do
    user = users(:trial_user)
    account = accounts(:trial_account)
    account.update!(
      current_plan: "trial",
      trial_ends_at: 10.days.from_now,
      cached_events_used: 0,
      cached_ai_summaries_used: 0,
      cached_pull_requests_used: 0,
      usage_cached_at: Time.current
    )
    sign_in user

    get usage_path
    assert_response :success

    refute_includes response.body, "Add Payment Method"
    refute_includes response.body, "billing_portal"
  end
end
