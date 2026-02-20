require "test_helper"

class TrialPlanLifecycleTest < ActiveSupport::TestCase
  # ============================================================================
  # Account creation starts on trial plan
  # ============================================================================

  test "new account starts on trial plan with 14-day trial" do
    ActsAsTenant.without_tenant do
      user = User.create!(
        email: "lifecycle#{SecureRandom.hex(4)}@example.com",
        password: "Password1!",
        confirmed_at: Time.current
      )

      account = user.account
      assert_equal "trial", account.current_plan
      assert_equal "month", account.billing_interval
      assert_equal 50_000, account.event_quota
      assert account.trial_ends_at.present?
      assert account.on_trial?
      assert_in_delta 14.days.from_now, account.trial_ends_at, 5.seconds
    end
  end

  test "trial account gets team-level quotas via effective_plan_key" do
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 7.days.from_now)

    assert account.on_trial?
    assert_equal :trial, account.send(:effective_plan_key)
    assert_equal "Free Trial", account.effective_plan_name
    assert_equal 50_000, account.event_quota_value
    assert_equal 20, account.ai_summaries_quota
    assert account.slack_notifications_allowed?
  end

  # ============================================================================
  # Trial expiration without payment -> free plan
  # ============================================================================

  test "expired trial without subscription falls back to free plan quotas" do
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 1.day.ago)

    refute account.on_trial?
    assert account.trial_expired?

    account.stub(:has_payment_method?, false) do
      account.stub(:active_subscription?, false) do
        assert_equal :free, account.send(:effective_plan_key)
        assert_equal 5_000, account.event_quota_value
        assert_equal 0, account.ai_summaries_quota
        refute account.slack_notifications_allowed?
      end
    end
  end

  # ============================================================================
  # Payment upgrades trial to paid plan
  # ============================================================================

  test "active subscription upgrades trial to team" do
    account = accounts(:trial_account)
    account.update!(current_plan: "team", trial_ends_at: nil)

    refute account.on_trial?
    assert_equal :team, account.send(:effective_plan_key)
    assert_equal "Team", account.effective_plan_name
  end

  test "active subscription with expired trial still returns paid plan" do
    account = accounts(:trial_account)
    account.update!(current_plan: "team", trial_ends_at: 1.week.ago)

    user = users(:trial_user)
    pay_customer = Pay::Customer.find_or_create_by!(
      owner_type: "User",
      owner_id: user.id,
      processor: "stripe"
    ) { |c| c.processor_id = "cus_lifecycle_test" }

    Pay::Subscription.create!(
      customer_id: pay_customer.id,
      processor_id: "sub_lifecycle_test_#{SecureRandom.hex(4)}",
      name: "default",
      processor_plan: "price_test",
      status: "active",
      quantity: 1
    )

    assert_equal :team, account.send(:effective_plan_key)
  end

  # ============================================================================
  # Plan name display
  # ============================================================================

  test "effective_plan_name returns Free Trial for trial accounts" do
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 7.days.from_now)
    assert_equal "Free Trial", account.effective_plan_name
  end

  test "effective_plan_name returns Team for paid team accounts" do
    account = accounts(:team_account)
    assert_equal "Team", account.effective_plan_name
  end

  test "effective_plan_name returns Free for free accounts" do
    account = accounts(:free_account)
    assert_equal "Free", account.effective_plan_name
  end

  # ============================================================================
  # needing_payment_reminder scope catches expired trial accounts
  # ============================================================================

  test "needing_payment_reminder includes expired trial accounts" do
    ActsAsTenant.without_tenant do
      account = accounts(:trial_account)
      account.update!(current_plan: "trial", trial_ends_at: 1.day.ago)

      result = Account.needing_payment_reminder
      assert_includes result, account
    end
  end

  test "needing_payment_reminder excludes active trial accounts" do
    ActsAsTenant.without_tenant do
      account = accounts(:trial_account)
      account.update!(current_plan: "trial", trial_ends_at: 7.days.from_now)

      result = Account.needing_payment_reminder
      refute_includes result, account
    end
  end
end
