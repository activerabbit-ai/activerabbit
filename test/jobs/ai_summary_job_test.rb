require "test_helper"

class AiSummaryJobTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
  end

  test "generates AI summary for a new issue" do
    # Create an event/issue to summarize
    payload = {
      exception_class: "AiTestError",
      message: "Error needing AI summary",
      backtrace: ["app/models/user.rb:10:in `save'"],
      controller_action: "UsersController#create",
      environment: "production"
    }

    event = Event.ingest_error(project: @project, payload: payload)
    issue = event.issue
    assert issue.ai_summary.blank?, "Issue should start without AI summary"

    # Stub external AI call
    AiSummaryService.stub(:new, ->(*args) {
      OpenStruct.new(call: { summary: "This error occurs when saving a user record." })
    }) do
      AiSummaryJob.new.perform(issue.id, event.id, @project.id)
    end

    issue.reload
    assert_equal "This error occurs when saving a user record.", issue.ai_summary
    assert issue.ai_summary_generated_at.present?
  end

  test "skips if AI summary already present (race condition guard)" do
    payload = {
      exception_class: "AlreadySummarizedError",
      message: "Already has summary",
      backtrace: [],
      controller_action: "HomeController#index",
      environment: "production"
    }

    event = Event.ingest_error(project: @project, payload: payload)
    issue = event.issue
    issue.update!(ai_summary: "Existing summary", ai_summary_generated_at: Time.current)

    # AiSummaryService should NOT be called
    AiSummaryService.stub(:new, ->(*args) {
      raise "Should not be called!"
    }) do
      assert_nothing_raised do
        AiSummaryJob.new.perform(issue.id, event.id, @project.id)
      end
    end

    issue.reload
    assert_equal "Existing summary", issue.ai_summary
  end

  test "skips when account is over AI summary quota" do
    payload = {
      exception_class: "QuotaTestError",
      message: "Over quota",
      backtrace: [],
      controller_action: "HomeController#index",
      environment: "production"
    }

    event = Event.ingest_error(project: @project, payload: payload)
    issue = event.issue

    # Stub within_quota? on the Account class so the freshly-loaded
    # account inside the job also returns false
    original_method = Account.instance_method(:within_quota?)
    Account.define_method(:within_quota?) { |*_args| false }

    AiSummaryService.stub(:new, ->(*args) {
      raise "Should not be called when over quota!"
    }) do
      assert_nothing_raised do
        AiSummaryJob.new.perform(issue.id, event.id, @project.id)
      end
    end

    issue.reload
    assert_nil issue.ai_summary
  ensure
    Account.define_method(:within_quota?, original_method)
  end

  test "skips when team plan has no active subscription" do
    payload = {
      exception_class: "TeamNoSubError",
      message: "No subscription",
      backtrace: [],
      controller_action: "HomeController#index",
      environment: "production"
    }

    event = Event.ingest_error(project: @project, payload: payload)
    issue = event.issue

    # team_account has trial_ends_at: nil (not on trial), no Pay::Subscription
    team_account = accounts(:team_account)
    team_account.update!(cached_ai_summaries_used: 0)

    # Stub the issue's account to use team_account
    original_method = Account.instance_method(:active_subscription?)
    Account.define_method(:active_subscription?) { false }

    # Also make effective_plan_key return :team
    original_plan_key = Account.instance_method(:effective_plan_key)
    Account.define_method(:effective_plan_key) { :team }

    AiSummaryService.stub(:new, ->(*args) {
      raise "Should not be called when team plan has no subscription!"
    }) do
      assert_nothing_raised do
        AiSummaryJob.new.perform(issue.id, event.id, @project.id)
      end
    end

    issue.reload
    assert_nil issue.ai_summary
  ensure
    Account.define_method(:active_subscription?, original_method) if original_method
    Account.define_method(:effective_plan_key, original_plan_key) if original_plan_key
  end

  test "does not raise on missing records" do
    assert_nothing_raised do
      AiSummaryJob.new.perform(999999, 999999, 999999)
    end
  end
end
