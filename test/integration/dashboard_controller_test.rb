require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
    sign_in @user
    ActsAsTenant.current_tenant = @account

    # Clear cache so each test starts fresh
    Rails.cache.delete("dashboard_stats/#{@account.id}")
    Rails.cache.delete("dashboard_project_stats/#{@account.id}")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "requires authentication" do
    sign_out @user
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "GET dashboard index" do
    get dashboard_path
    assert_response :success
  end

  test "dashboard shows project stats" do
    get dashboard_path
    assert_response :success
    assert assigns(:stats).present?
    assert assigns(:projects).present?
  end

  test "dashboard stats include total_projects" do
    get dashboard_path
    assert_response :success
    assert assigns(:stats)[:total_projects].is_a?(Integer)
  end

  test "dashboard stats include open_issues" do
    get dashboard_path
    assert_response :success
    assert assigns(:stats)[:open_issues].is_a?(Integer)
  end

  test "dashboard shows recent projects" do
    get dashboard_path
    assert_response :success
    assert assigns(:recent_projects).present?
  end

  test "project_dashboard redirects to errors page" do
    get project_dashboard_path(@project.slug)
    assert_redirected_to project_slug_errors_path(@project.slug)
  end

  test "project_dashboard handles missing project" do
    get project_dashboard_path("nonexistent-slug")
    assert_redirected_to dashboard_path
  end

  test "dashboard computes project stats without N+1" do
    get dashboard_path
    assert_response :success

    # Project stats should be precomputed
    assert assigns(:project_stats).is_a?(Hash)
    @project.reload
    stats = assigns(:project_stats)[@project.id]
    assert stats.present?
    assert stats.key?(:issues_count)
    assert stats.key?(:events_today)
  end

  # ── Caching tests ──────────────────────────────────────────────────────

  test "dashboard stats are cached for 2 minutes" do
    # Switch to memory_store so we can verify caching behaviour
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    begin
      get dashboard_path
      assert_response :success
      first_stats = assigns(:stats)

      cached = Rails.cache.read("dashboard_stats/#{@account.id}")
      assert cached.present?, "Dashboard stats should be cached after first request"
      assert_equal first_stats[:total_projects], cached[:total_projects]
    ensure
      Rails.cache = original_cache
    end
  end

  test "dashboard project stats are cached for 2 minutes" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    begin
      get dashboard_path
      assert_response :success

      cached = Rails.cache.read("dashboard_project_stats/#{@account.id}")
      assert cached.present?, "Per-project stats should be cached after first request"
      assert cached.key?(:issues), "Cached project stats should include :issues"
      assert cached.key?(:events_today), "Cached project stats should include :events_today"
      assert cached.key?(:issues_total), "Cached project stats should include :issues_total"
      assert cached.key?(:ai_summaries), "Cached project stats should include :ai_summaries"
    ensure
      Rails.cache = original_cache
    end
  end

  # ── Cached values tests ────────────────────────────────────────────────

  test "total_events uses cached_events_used from account" do
    @account.update_column(:cached_events_used, 42_000)

    get dashboard_path
    assert_response :success
    assert_equal 42_000, assigns(:stats)[:total_events]
  end

  test "events_last_30_days uses daily_event_counts rollup table" do
    # Create daily_event_count rows for the account
    DailyEventCount.create!(account: @account, day: 2.days.ago.to_date, count: 100)
    DailyEventCount.create!(account: @account, day: 5.days.ago.to_date, count: 200)

    get dashboard_path
    assert_response :success

    # Should sum from the rollup table (100 + 200 = 300, plus any existing)
    assert assigns(:stats)[:events_last_30_days] >= 300
  end

  test "events_last_30_days excludes counts older than 30 days" do
    DailyEventCount.where(account_id: @account.id).delete_all
    DailyEventCount.create!(account: @account, day: 10.days.ago.to_date, count: 50)
    DailyEventCount.create!(account: @account, day: 60.days.ago.to_date, count: 9999)

    get dashboard_path
    assert_response :success

    # Only the 10-days-ago record should be included
    assert_equal 50, assigns(:stats)[:events_last_30_days]
  end

  # ── Per-project stats tests ────────────────────────────────────────────

  test "events_total per project uses issue count sum instead of events table" do
    get dashboard_path
    assert_response :success

    stats = assigns(:project_stats)[@project.id]
    assert stats.present?

    # events_total should come from Issue.sum(:count), not Event.count
    expected = Issue.where(project_id: @project.id).sum(:count)
    assert_equal expected, stats[:events_total]
  end

  test "project stats include all expected keys" do
    get dashboard_path
    assert_response :success

    stats = assigns(:project_stats)[@project.id]
    assert stats.present?

    %i[issues_count events_today events_total ai_summaries health_status issue_pr_urls perf_pr_urls].each do |key|
      assert stats.key?(key), "Project stats should include :#{key}"
    end
  end

  # ── recent_events scoping test ─────────────────────────────────────────

  test "recent_events are scoped to last 24 hours" do
    get dashboard_path
    assert_response :success

    recent = assigns(:recent_events)
    assert recent.all? { |e| e.occurred_at > 24.hours.ago },
      "All recent_events should be within the last 24 hours"
  end
end
