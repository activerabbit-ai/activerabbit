require "test_helper"

class DunningFollowupJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
  end

  test "sends payment failed email" do
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:payment_failed, ->(**args) {
      assert_equal @account, args[:account]
      assert_equal "inv_123", args[:invoice_id]
      mock_mail
    }) do
      DunningFollowupJob.perform_now(account_id: @account.id, invoice_id: "inv_123")
    end

    assert mock_mail.verify
  end

  test "handles account not found gracefully" do
    # Should not raise, just return early
    assert_nothing_raised do
      DunningFollowupJob.perform_now(account_id: 999999, invoice_id: "inv_123")
    end
  end

  test "passes invoice_id to mailer" do
    invoice_id = "inv_test_456"
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:payment_failed, ->(**args) {
      assert_equal invoice_id, args[:invoice_id]
      mock_mail
    }) do
      DunningFollowupJob.perform_now(account_id: @account.id, invoice_id: invoice_id)
    end

    assert mock_mail.verify
  end
end
