require "test_helper"

class SendWelcomeEmailJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:owner)
    @reset_token = "test_reset_token_123"
  end

  test "sends welcome email to the user" do
    mock_mail = Minitest::Mock.new
    mock_mail.expect :deliver_now, true

    UserMailer.stub :welcome_and_setup_password, ->(*args) { mock_mail } do
      SendWelcomeEmailJob.new.perform(@user.id, @reset_token)
    end

    assert mock_mail.verify
  end

  test "raises RecordNotFound when user does not exist" do
    assert_raises(ActiveRecord::RecordNotFound) do
      SendWelcomeEmailJob.new.perform(-1, @reset_token)
    end
  end

  test "job has retry set to 3" do
    assert_equal 3, SendWelcomeEmailJob.sidekiq_options["retry"]
  end
end
