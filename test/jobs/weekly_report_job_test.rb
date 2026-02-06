require "test_helper"
require "ostruct"

class WeeklyReportJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @account.update!(
      name: "Test Account",
      cached_events_used: 100,
      usage_cached_at: Time.current
    )

    # Use memory store for cache
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.clear
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "uses week-based cache key" do
    week_key = Date.current.beginning_of_week.to_s
    cache_key = "weekly_report:#{@account.id}:#{week_key}"

    refute Rails.cache.exist?(cache_key)

    # Stub the mailer to avoid actual sending - use a fake that always returns a deliverable
    fake_mailer = Object.new
    def fake_mailer.weekly_report
      fake_mail = Object.new
      def fake_mail.deliver_now; true; end
      fake_mail
    end

    WeeklyReportMailer.stub :with, ->(*args) { fake_mailer } do
      WeeklyReportJob.new.perform(@account.id)
    end

    assert Rails.cache.exist?(cache_key)
  end

  test "does not send when account has no stats" do
    @account.update!(
      cached_events_used: 0,
      cached_performance_events_used: 0,
      cached_ai_summaries_used: 0,
      cached_pull_requests_used: 0,
      usage_cached_at: Time.current
    )

    # Should not call mailer
    WeeklyReportMailer.stub :with, ->(*args) { raise "Should not be called" } do
      assert_nothing_raised do
        WeeklyReportJob.new.perform(@account.id)
      end
    end
  end

  test "does not send when usage_cached_at is nil" do
    @account.update!(usage_cached_at: nil)

    WeeklyReportMailer.stub :with, ->(*args) { raise "Should not be called" } do
      assert_nothing_raised do
        WeeklyReportJob.new.perform(@account.id)
      end
    end
  end
end
