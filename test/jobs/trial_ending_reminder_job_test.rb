require "test_helper"

class TrialEndingReminderJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:trial_account)
  end

  test "sends trial ending reminder email" do
    mock_mailer = Minitest::Mock.new
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)
    mock_mailer.expect(:trial_ending_soon, mock_mail, account: @account, days_left: 4)

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      mock_mail
    }) do
      TrialEndingReminderJob.perform_now(account_id: @account.id, days_left: 4)
    end

    assert mock_mail.verify
  end

  test "handles custom days_left parameter" do
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      assert_equal 7, args[:days_left]
      mock_mail
    }) do
      TrialEndingReminderJob.perform_now(account_id: @account.id, days_left: 7)
    end

    assert mock_mail.verify
  end

  test "does nothing when account not found" do
    # Should not raise, just return early
    assert_nothing_raised do
      TrialEndingReminderJob.perform_now(account_id: 999999, days_left: 4)
    end
  end

  test "uses default days_left of 4" do
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      assert_equal 4, args[:days_left]
      mock_mail
    }) do
      TrialEndingReminderJob.perform_now(account_id: @account.id)
    end

    assert mock_mail.verify
  end
end
