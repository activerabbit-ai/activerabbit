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
    @account.update!(trial_ends_at: 1.day.ago, current_plan: "team", event_quota: 100_000)

    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_expired_downgraded, ->(**args) {
      assert_equal @account, args[:account]
      assert_equal "team", args[:previous_plan]
      mock_mail
    }) do
      TrialExpirationJob.perform_now
    end

    @account.reload
    assert_equal "free", @account.current_plan
    assert_equal 5_000, @account.event_quota
  end

  test "does not downgrade account still on trial" do
    @account.update!(trial_ends_at: 5.days.from_now, current_plan: "team")

    TrialExpirationJob.perform_now

    @account.reload
    assert_equal "team", @account.current_plan
  end

  test "does not downgrade account already on free plan" do
    @account.update!(trial_ends_at: 1.day.ago, current_plan: "free")

    TrialExpirationJob.perform_now

    @account.reload
    assert_equal "free", @account.current_plan
  end

  test "does not downgrade inactive accounts" do
    @account.update!(trial_ends_at: 1.day.ago, current_plan: "team", active: false)

    TrialExpirationJob.perform_now

    @account.reload
    assert_equal "team", @account.current_plan
  end

  test "does not downgrade accounts with active subscription" do
    @account.update!(trial_ends_at: 1.day.ago, current_plan: "team")

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
    assert_equal "team", @account.current_plan
  end

  # ============================================================================
  # Sends downgrade notification email
  # ============================================================================

  test "sends downgrade notification email" do
    @account.update!(trial_ends_at: 1.day.ago, current_plan: "team")

    email_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_expired_downgraded, ->(**args) {
      email_sent = true
      assert_equal "team", args[:previous_plan]
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
    @account.update!(trial_ends_at: 1.day.ago, current_plan: "team")

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
