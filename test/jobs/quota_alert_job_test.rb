require "test_helper"

class QuotaAlertJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @user = users(:owner)

    # Stub Resend API
    stub_request(:post, "https://api.resend.com/emails")
      .to_return(status: 200, body: '{"id": "test-email-id"}', headers: { "Content-Type" => "application/json" })
  end

  test "checks quotas for all accounts" do
    assert_nothing_raised do
      QuotaAlertJob.new.perform
    end
  end

  test "handles account with no confirmed users gracefully" do
    # Create account with only unconfirmed user
    new_account = Account.create!(
      name: "Test No Users",
      current_plan: "free",
      cached_events_used: 6000,
      usage_cached_at: Time.current
    )

    # No confirmed users

    assert_nothing_raised do
      QuotaAlertJob.new.perform
    end
  end

  test "handles account with zero usage gracefully" do
    @account.update!(
      cached_events_used: 0,
      cached_ai_summaries_used: 0,
      cached_pull_requests_used: 0,
      usage_cached_at: Time.current
    )

    assert_nothing_raised do
      QuotaAlertJob.new.perform
    end
  end
end
