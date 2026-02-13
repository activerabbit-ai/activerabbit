require "test_helper"

class TrialReminderCheckJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:trial_account)
    # Reset any memoized state
    ActsAsTenant.current_tenant = nil
  end

  # ============================================================================
  # Sends reminders at correct day intervals
  # ============================================================================

  test "sends 8-day reminder for account with trial ending in 8 days" do
    @account.update!(trial_ends_at: 8.days.from_now)

    mail_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      assert_equal @account, args[:account]
      assert_equal 8, args[:days_left]
      mail_sent = true
      mock_mail
    }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
        TrialReminderCheckJob.perform_now
      end
    end

    assert mail_sent, "Should have sent 8-day reminder"
  end

  test "sends 4-day reminder for account with trial ending in 4 days" do
    @account.update!(trial_ends_at: 4.days.from_now)

    mail_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      if args[:days_left] == 4
        mail_sent = true
      end
      mock_mail
    }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
        TrialReminderCheckJob.perform_now
      end
    end

    assert mail_sent, "Should have sent 4-day reminder"
  end

  test "sends 2-day reminder for account with trial ending in 2 days" do
    @account.update!(trial_ends_at: 2.days.from_now)

    mail_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      if args[:days_left] == 2
        mail_sent = true
      end
      mock_mail
    }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
        TrialReminderCheckJob.perform_now
      end
    end

    assert mail_sent, "Should have sent 2-day reminder"
  end

  test "sends 1-day reminder for account with trial ending in 1 day" do
    @account.update!(trial_ends_at: 1.day.from_now)

    mail_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      if args[:days_left] == 1
        mail_sent = true
      end
      mock_mail
    }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
        TrialReminderCheckJob.perform_now
      end
    end

    assert mail_sent, "Should have sent 1-day reminder"
  end

  test "sends trial-ends-today for account with trial ending today" do
    @account.update!(trial_ends_at: Time.current)

    today_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) { Minitest::Mock.new }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) {
        assert_equal @account, args[:account]
        today_sent = true
        mock_mail
      }) do
        TrialReminderCheckJob.perform_now
      end
    end

    assert today_sent, "Should have sent trial-ends-today email"
  end

  # ============================================================================
  # Does NOT send for non-matching days
  # ============================================================================

  test "does not send reminder for account with trial ending in 5 days" do
    @account.update!(trial_ends_at: 5.days.from_now)

    mail_sent = false

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      mail_sent = true
      Minitest::Mock.new
    }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
        TrialReminderCheckJob.perform_now
      end
    end

    refute mail_sent, "Should NOT have sent a reminder for 5-day account"
  end

  test "does not send pre-expiry reminder for already expired trial" do
    @account.update!(trial_ends_at: 3.days.ago)

    pre_expiry_sent = false

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      pre_expiry_sent = true
      Minitest::Mock.new
    }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
        LifecycleMailer.stub(:trial_expired_warning, ->(**args) {
          mock = Minitest::Mock.new
          mock.expect(:deliver_now, true)
          mock
        }) do
          TrialReminderCheckJob.perform_now
        end
      end
    end

    refute pre_expiry_sent, "Should NOT send pre-expiry reminder for already expired trial"
  end

  # ============================================================================
  # Skips accounts with active subscription
  # ============================================================================

  test "skips accounts with active subscription" do
    @account.update!(trial_ends_at: 4.days.from_now)

    mail_sent = false

    # Stub active_subscription? to return true
    Account.any_instance.stub(:active_subscription?, true) do
      LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
        mail_sent = true
        Minitest::Mock.new
      }) do
        LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
          TrialReminderCheckJob.perform_now
        end
      end
    end

    refute mail_sent, "Should NOT send reminder if account has active subscription"
  end

  # ============================================================================
  # Skips inactive accounts
  # ============================================================================

  test "skips inactive accounts" do
    @account.update!(trial_ends_at: 4.days.from_now, active: false)

    mail_sent = false

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      mail_sent = true
      Minitest::Mock.new
    }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
        TrialReminderCheckJob.perform_now
      end
    end

    refute mail_sent, "Should NOT send reminder for inactive account"
  end

  # ============================================================================
  # Post-expiry warnings (2, 4, 6, 8 days after trial ended)
  # ============================================================================

  test "sends 2-day post-expiry warning for account whose trial expired 2 days ago" do
    @account.update!(trial_ends_at: 2.days.ago)

    warning_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    stub_all_mailers do
      LifecycleMailer.stub(:trial_expired_warning, ->(**args) {
        assert_equal @account, args[:account]
        assert_equal 2, args[:days_since_expired]
        warning_sent = true
        mock_mail
      }) do
        TrialReminderCheckJob.perform_now
      end
    end

    assert warning_sent, "Should have sent 2-day post-expiry warning"
  end

  test "sends 4-day post-expiry warning for account whose trial expired 4 days ago" do
    @account.update!(trial_ends_at: 4.days.ago)

    warning_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    stub_all_mailers do
      LifecycleMailer.stub(:trial_expired_warning, ->(**args) {
        if args[:days_since_expired] == 4
          warning_sent = true
        end
        mock_mail
      }) do
        TrialReminderCheckJob.perform_now
      end
    end

    assert warning_sent, "Should have sent 4-day post-expiry warning"
  end

  test "sends 6-day post-expiry warning for account whose trial expired 6 days ago" do
    @account.update!(trial_ends_at: 6.days.ago)

    warning_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    stub_all_mailers do
      LifecycleMailer.stub(:trial_expired_warning, ->(**args) {
        if args[:days_since_expired] == 6
          warning_sent = true
        end
        mock_mail
      }) do
        TrialReminderCheckJob.perform_now
      end
    end

    assert warning_sent, "Should have sent 6-day post-expiry warning"
  end

  test "sends 8-day post-expiry warning for account whose trial expired 8 days ago" do
    @account.update!(trial_ends_at: 8.days.ago)

    warning_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    stub_all_mailers do
      LifecycleMailer.stub(:trial_expired_warning, ->(**args) {
        if args[:days_since_expired] == 8
          warning_sent = true
        end
        mock_mail
      }) do
        TrialReminderCheckJob.perform_now
      end
    end

    assert warning_sent, "Should have sent 8-day post-expiry warning"
  end

  test "does not send post-expiry warning for non-matching days (e.g. 3 days ago)" do
    @account.update!(trial_ends_at: 3.days.ago)

    warning_sent = false

    stub_all_mailers do
      LifecycleMailer.stub(:trial_expired_warning, ->(**args) {
        warning_sent = true
        Minitest::Mock.new
      }) do
        TrialReminderCheckJob.perform_now
      end
    end

    refute warning_sent, "Should NOT send post-expiry warning for 3-day gap"
  end

  test "skips post-expiry warning if account has active subscription" do
    @account.update!(trial_ends_at: 2.days.ago)

    warning_sent = false

    Account.any_instance.stub(:active_subscription?, true) do
      stub_all_mailers do
        LifecycleMailer.stub(:trial_expired_warning, ->(**args) {
          warning_sent = true
          Minitest::Mock.new
        }) do
          TrialReminderCheckJob.perform_now
        end
      end
    end

    refute warning_sent, "Should NOT send post-expiry warning if account upgraded"
  end

  # ============================================================================
  # Error handling
  # ============================================================================

  test "continues processing other accounts if one fails" do
    # Create a second account also ending in 8 days
    other_account = accounts(:default)
    other_account.update!(trial_ends_at: 8.days.from_now)
    @account.update!(trial_ends_at: 8.days.from_now)

    call_count = 0

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      call_count += 1
      if call_count == 1
        raise "Simulated mailer error"
      end
      mock_mail_ok = Minitest::Mock.new
      mock_mail_ok.expect(:deliver_now, true)
      mock_mail_ok
    }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
        LifecycleMailer.stub(:trial_expired_warning, ->(**args) { Minitest::Mock.new }) do
          assert_nothing_raised do
            TrialReminderCheckJob.perform_now
          end
        end
      end
    end

    assert call_count >= 2, "Should have attempted to send to multiple accounts"
  end

  private

  # Helper to stub mailers that aren't being tested
  def stub_all_mailers(&block)
    noop = ->(**args) { Minitest::Mock.new }
    LifecycleMailer.stub(:trial_ending_soon, noop) do
      LifecycleMailer.stub(:trial_end_today, noop, &block)
    end
  end
end
