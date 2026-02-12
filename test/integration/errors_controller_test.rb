require "test_helper"

class ErrorsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
    sign_in @user
    ActsAsTenant.current_tenant = @account
  end

  teardown do
    ActsAsTenant.current_tenant = nil
    Rails.cache.clear
  end

  # === Authentication ===

  test "requires authentication" do
    sign_out @user
    get errors_path
    assert_redirected_to new_user_session_path
  end

  # === Basic loading ===

  test "GET index loads successfully" do
    get errors_path
    assert_response :success
  end

  test "GET index with issues" do
    get errors_path
    assert_response :success
    assert_not_nil assigns(:issues)
    assert_not_nil assigns(:total_errors)
    assert_not_nil assigns(:open_errors)
    assert_not_nil assigns(:resolved_errors)
    assert_not_nil assigns(:recent_errors)
    assert_not_nil assigns(:failed_jobs_count)
  end

  # === Grouped count summary stats ===

  test "summary stats use grouped count correctly" do
    get errors_path
    assert_response :success

    total = assigns(:total_errors)
    wip_count = assigns(:open_errors)
    closed_count = assigns(:resolved_errors)

    assert total.is_a?(Integer)
    assert wip_count.is_a?(Integer)
    assert closed_count.is_a?(Integer)

    # wip_issue is status="wip"
    assert_equal 1, wip_count
    # closed_issue is status="closed"
    assert_equal 1, closed_count
    # total should be sum of all statuses (excluding issues seen <1 minute ago)
    cutoff = 1.minute.ago
    expected_open = Issue.where(account_id: @account.id).open.where("last_seen_at < ?", cutoff).count
    assert_equal total, wip_count + closed_count + expected_open
  end

  # === Recent errors count ===

  test "recent errors counts issues seen in last 24h but older than 1 minute" do
    get errors_path
    assert_response :success

    recent = assigns(:recent_errors)
    assert recent.is_a?(Integer)

    # Counts issues with last_seen_at between 24h ago and 1 minute ago
    expected = Issue.where(account_id: @account.id)
                    .where("last_seen_at > ?", 24.hours.ago)
                    .where("last_seen_at < ?", 1.minute.ago)
                    .count
    assert_equal expected, recent
  end

  # === Failed jobs count caching ===

  test "failed_jobs_count is cached" do
    get errors_path
    assert_response :success
    first_count = assigns(:failed_jobs_count)

    # Second request should hit cache
    get errors_path
    assert_response :success
    assert_equal first_count, assigns(:failed_jobs_count)
  end

  # === Job failure detection via controller_action heuristic ===

  test "detects job failure issues via controller_action" do
    get errors_path
    assert_response :success

    job_ids = assigns(:issue_ids_with_job_failures)
    assert job_ids.is_a?(Set)

    job_issue = issues(:job_failure_issue)
    open_issue = issues(:open_issue)

    # SyncWorker does NOT contain "Controller#" -> detected as job
    assert_includes job_ids, job_issue.id
    # HomeController#index DOES contain "Controller#" -> not a job
    refute_includes job_ids, open_issue.id
  end

  # === Events 24h impact metrics ===

  test "calculates events_24h_by_issue_id" do
    # Pass period=all to ensure all issues show up in the list
    get errors_path, params: { period: "all" }
    assert_response :success

    events_24h = assigns(:events_24h_by_issue_id)
    assert events_24h.is_a?(Hash)

    # open_issue has events: default(now), recent(5min ago),
    #   recent_event_for_open(2h ago) = all within 24h
    #   very_old_event_for_open(3 days ago) = outside 24h
    open_issue = issues(:open_issue)
    count = events_24h[open_issue.id] || 0
    assert count >= 2, "Expected at least 2 recent events for open_issue, got #{count}"
  end

  test "empty metrics when no issues on page" do
    # Delete events first (FK constraint), then issues
    Event.where(account_id: @account.id).delete_all
    Issue.where(account_id: @account.id).delete_all

    get errors_path
    assert_response :success

    assert_equal 0, assigns(:total_events_24h)
    assert_equal({}, assigns(:events_24h_by_issue_id))
    assert_equal Set.new, assigns(:issue_ids_with_job_failures)
  end

  # === Filters ===

  test "defaults to showing all errors" do
    get errors_path
    assert_response :success

    assert_equal "all", assigns(:current_period)

    # All issues (older than 1 minute) should be visible by default
    issues = assigns(:issues)
    old_issue = issues(:old_issue)
    assert_includes issues.map(&:id), old_issue.id
  end

  test "period=all shows all issues" do
    get errors_path, params: { period: "all" }
    assert_response :success

    assert_equal "all", assigns(:current_period)
  end

  test "filters by period=1d" do
    get errors_path, params: { period: "1d" }
    assert_response :success

    issues = assigns(:issues)
    # old_issue has last_seen_at 3 days ago, should be filtered out
    old_issue = issues(:old_issue)
    refute_includes issues.map(&:id), old_issue.id
  end

  test "filters by filter=closed" do
    get errors_path, params: { filter: "closed" }
    assert_response :success

    issues = assigns(:issues)
    issues.each do |issue|
      assert_equal "closed", issue.status
    end
  end

  test "filters by filter=open returns wip issues" do
    get errors_path, params: { filter: "open" }
    assert_response :success

    issues = assigns(:issues)
    issues.each do |issue|
      assert_equal "wip", issue.status
    end
  end

  test "filters by filter=jobs returns job failure issues" do
    get errors_path, params: { filter: "jobs" }
    assert_response :success

    issues = assigns(:issues)
    # job_failure_issue fixture has controller_action="SyncWorker" and a job event
    job_issue = issues(:job_failure_issue)
    if issues.any?
      assert_includes issues.map(&:id), job_issue.id
    end
  end

  # === Project-scoped ===

  test "GET project-scoped errors index" do
    get project_errors_path(@project)
    assert_response :success

    total = assigns(:total_errors)
    assert total.is_a?(Integer)
    # All test fixtures belong to default project so total should match
    assert total > 0
  end

  # === Show page still works ===

  test "GET show page loads" do
    issue = issues(:open_issue)
    get error_path(issue)
    assert_response :success
    assert_not_nil assigns(:events_24h)
  end

  # === AI Quota — ERB-only checks (no JS quota card) ===

  test "show page does NOT contain hidden JS quota message text" do
    issue = issues(:open_issue)
    get error_path(issue)
    assert_response :success
    assert_no_match(/AI analysis quota reached\.\s*<\/span>/, response.body,
      "The old hidden JS quota message div should not exist in the page")
  end

  test "show page renders Generate AI button when within quota" do
    @account.update_columns(cached_ai_summaries_used: 2, current_plan: "team")
    issue = issues(:open_issue)
    issue.update_columns(ai_summary: nil)

    get error_path(issue)
    assert_response :success
    assert_match(/Generate AI/, response.body,
      "Should show 'Generate AI' button when within quota")
  end

  test "show page renders quota exceeded UI when over quota" do
    @account.update_columns(cached_ai_summaries_used: 100, current_plan: "team")
    issue = issues(:open_issue)
    issue.update_columns(ai_summary: nil)

    get error_path(issue)
    assert_response :success
    assert_match(/AI Analysis Limit Reached|Buy More|Upgrade/, response.body,
      "Should show quota exceeded UI when over quota")
    assert_no_match(/Generate AI/, response.body,
      "Should NOT show Generate AI button when over quota")
  end

  test "show page does NOT have quota-exceeded or upgrade-url data attributes on generate button" do
    @account.update_columns(cached_ai_summaries_used: 0, current_plan: "team")
    issue = issues(:open_issue)
    issue.update_columns(ai_summary: nil)

    get error_path(issue)
    assert_response :success
    assert_no_match(/data-generate-ai-quota-exceeded-value/, response.body,
      "Should not have quota-exceeded data attribute")
    assert_no_match(/data-generate-ai-upgrade-url-value/, response.body,
      "Should not have upgrade-url data attribute")
  end

  # === regenerate_ai_summary — quota exceeded returns simple JSON ===

  test "regenerate_ai_summary returns simple JSON on quota exceeded" do
    @account.update_columns(cached_ai_summaries_used: 100, current_plan: "team")
    issue = issues(:open_issue)

    post regenerate_ai_summary_error_path(issue),
         headers: { "Accept" => "application/json", "X-Requested-With" => "XMLHttpRequest" }

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_equal true, json["quota_exceeded"]
    # Should NOT contain the old JS-specific fields
    assert_nil json["can_buy_more"], "Should not include can_buy_more in response"
    assert_nil json["message"], "Should not include message in response"
    assert_nil json["upgrade_url"], "Should not include upgrade_url in response"
  end

  test "regenerate_ai_summary redirects with flash on HTML quota exceeded" do
    @account.update_columns(cached_ai_summaries_used: 100, current_plan: "team")
    issue = issues(:open_issue)

    post regenerate_ai_summary_error_path(issue)

    assert_response :redirect
    assert_equal "AI analysis quota reached.", flash[:alert]
  end

  # === index page — quota badges are ERB only ===

  test "index shows gray AI badge when within quota and no summary" do
    @account.update_columns(cached_ai_summaries_used: 2, current_plan: "team")
    issue = issues(:open_issue)
    issue.update_columns(ai_summary: nil)

    get errors_path
    assert_response :success
    # Should not show upgrade/buy more badges
    assert_no_match(/AI quota reached/, response.body)
  end

  test "index shows upgrade badge when over quota on free plan" do
    @account.update_columns(
      cached_ai_summaries_used: 5,
      current_plan: "free",
      trial_ends_at: 1.day.ago
    )
    issue = issues(:open_issue)
    issue.update_columns(ai_summary: nil)

    get errors_path
    assert_response :success
    assert_match(/Upgrade/, response.body)
  end
end
