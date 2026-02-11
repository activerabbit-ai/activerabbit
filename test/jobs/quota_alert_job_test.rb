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
    new_account = Account.create!(
      name: "Test No Users",
      current_plan: "free",
      cached_events_used: 6000,
      usage_cached_at: Time.current
    )
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

  # Throttle: re-send only when last_sent_at >= 1 day ago (REMIND_*_AFTER_DAYS = 1)
  test "does not re-send when last alert was less than 1 day ago" do
    @account.update!(
      cached_events_used: 4200,
      usage_cached_at: Time.current,
      current_plan: "free",
      trial_ends_at: 1.day.ago,
      last_quota_alert_sent_at: {
        "events" => {
          "sent_at" => 12.hours.ago.iso8601,
          "level" => "80_percent",
          "percentage" => 84.0
        }
      }
    )

    assert_no_difference "ActionMailer::Base.deliveries.size" do
      QuotaAlertJob.new.perform
    end
  end

  test "re-sends when last alert was 1+ day ago" do
    @account.update!(
      cached_events_used: 4200,
      usage_cached_at: Time.current,
      current_plan: "free",
      trial_ends_at: 1.day.ago,
      last_quota_alert_sent_at: {
        "events" => {
          "sent_at" => 2.days.ago.iso8601,
          "level" => "80_percent",
          "percentage" => 84.0
        }
      }
    )

    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      QuotaAlertJob.new.perform
    end
  end
end
