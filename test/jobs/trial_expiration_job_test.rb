require "test_helper"

class TrialExpirationJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:trial_account)
    ActsAsTenant.current_tenant = nil
  end

  # ============================================================================
  # Downgrades expired trials to Free
  # ============================================================================

  test "downgrades account to free when trial expired and no subscription" do
    @account.update!(
      trial_ends_at: 1.day.ago,
      current_plan: "trial",
      event_quota: 50_000,
      cached_events_used: 8_000,
      cached_ai_summaries_used: 15,
      cached_pull_requests_used: 10
    )

    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_expired_downgraded, ->(**args) {
      assert_equal @account, args[:account]
      assert_equal "trial", args[:previous_plan]
      mock_mail
    }) do
      TrialExpirationJob.perform_now
    end

    @account.reload
    assert_equal "free", @account.current_plan
    assert_equal 5_000, @account.event_quota

    # Usage counters should be reset on downgrade
    assert_equal 0, @account.cached_events_used, "Events should be reset on downgrade to free"
    assert_equal 0, @account.cached_ai_summaries_used, "AI summaries should be reset"
    assert_equal 0, @account.cached_pull_requests_used, "PRs should be reset"
  end

  test "does not downgrade account still on trial" do
    @account.update!(trial_ends_at: 5.days.from_now, current_plan: "trial")

    TrialExpirationJob.perform_now

    @account.reload
    assert_equal "trial", @account.current_plan
  end

  test "does not downgrade account already on free plan" do
    @account.update!(trial_ends_at: 1.day.ago, current_plan: "free")

    TrialExpirationJob.perform_now

    @account.reload
    assert_equal "free", @account.current_plan
  end

  test "does not downgrade inactive accounts" do
    @account.update!(trial_ends_at: 1.day.ago, current_plan: "trial", active: false)

    TrialExpirationJob.perform_now

    @account.reload
    assert_equal "trial", @account.current_plan
  end

  test "does not downgrade accounts with active subscription" do
    @account.update!(trial_ends_at: 1.day.ago, current_plan: "trial")

    # Create a user and Pay::Subscription to simulate active subscription
    user = User.find_by(account_id: @account.id)
    if user
      pay_customer = Pay::Customer.find_or_create_by!(
        owner_type: "User",
        owner_id: user.id,
        processor: "stripe"
      ) do |c|
        c.processor_id = "cus_test_#{SecureRandom.hex(4)}"
      end

      Pay::Subscription.create!(
        customer_id: pay_customer.id,
        processor_id: "sub_test_#{SecureRandom.hex(4)}",
        name: "default",
        processor_plan: "price_test",
        status: "active",
        quantity: 1
      )
    end

    TrialExpirationJob.perform_now

    @account.reload
    assert_equal "trial", @account.current_plan
  end

  # ============================================================================
  # Sends downgrade notification email
  # ============================================================================

  test "sends downgrade notification email" do
    @account.update!(trial_ends_at: 1.day.ago, current_plan: "trial")

    email_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_expired_downgraded, ->(**args) {
      email_sent = true
      assert_equal "trial", args[:previous_plan]
      mock_mail
    }) do
      TrialExpirationJob.perform_now
    end

    assert email_sent, "Should have sent downgrade notification email"
  end

  # ============================================================================
  # Error handling
  # ============================================================================

  test "continues processing if email delivery fails" do
    @account.update!(trial_ends_at: 1.day.ago, current_plan: "trial")

    LifecycleMailer.stub(:trial_expired_downgraded, ->(**args) {
      raise "Mailer error"
    }) do
      assert_nothing_raised do
        TrialExpirationJob.perform_now
      end
    end

    # Account should still be downgraded even if email fails
    @account.reload
    assert_equal "free", @account.current_plan
  end
end
