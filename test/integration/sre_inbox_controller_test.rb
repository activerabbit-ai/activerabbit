require "test_helper"

class SreInboxControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @account = accounts(:default)
    @user    = users(:owner)
    @project = projects(:default)
    sign_in @user
    ActsAsTenant.current_tenant = @account

    # Wipe any pre-existing fixtures (and dependent rows) so each test
    # seeds a deterministic set without tripping foreign-key constraints.
    Event.delete_all
    Issue.delete_all

    # Establish session[:selected_project_slug] = @project.slug by
    # visiting a project-scoped URL once. The inbox falls back to that
    # session value when no slug is in the URL.
    get "/#{@project.slug}/errors"
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  def make_issue(attrs)
    Issue.create!({
      account_id:        @account.id,
      project_id:        @project.id,
      fingerprint:       Digest::SHA256.hexdigest("fp-#{SecureRandom.hex(4)}"),
      exception_class:   "RuntimeError",
      top_frame:         "app/x.rb:1",
      controller_action: "X#y",
      status:            "open",
      count:             1,
      first_seen_at:     1.hour.ago,
      last_seen_at:      5.minutes.ago
    }.merge(attrs))
  end

  # Each helper creates one issue with the canonical bucket-defining attrs.
  def seed_one_per_bucket
    @merged       = make_issue(resolution_status: "resolved",        auto_fix_status: "merged",                   auto_fix_pr_number: 1)
    @resolved_nil = make_issue(resolution_status: "resolved",        auto_fix_status: nil)
    @needs_attn   = make_issue(resolution_status: "needs_attention", auto_fix_status: nil)
    @review_pr    = make_issue(resolution_status: nil,               auto_fix_status: "pr_created_review_needed", auto_fix_pr_number: 2)
    @ci_failed    = make_issue(resolution_status: nil,               auto_fix_status: "ci_failed",                auto_fix_pr_number: 3)
    @merge_failed = make_issue(resolution_status: nil,               auto_fix_status: "merge_failed",             auto_fix_pr_number: 4)
    @investigating = make_issue(resolution_status: "investigating",  auto_fix_status: nil)
    @ci_pending   = make_issue(resolution_status: nil,               auto_fix_status: "ci_pending",               auto_fix_pr_number: 5)
    @raw          = make_issue(resolution_status: nil,               auto_fix_status: nil)
  end

  # ── Auth ─────────────────────────────────────────────────────────────

  test "redirects to sign-in when unauthenticated" do
    sign_out @user
    get inbox_path
    assert_redirected_to new_user_session_path
  end

  # ── Smoke ────────────────────────────────────────────────────────────

  test "GET /inbox returns success" do
    get inbox_path
    assert_response :success
  end

  test "root path renders the inbox" do
    get root_path
    assert_response :success
    assert_select "title", text: /SRE Inbox/i
  end

  # ── Bucket counts ────────────────────────────────────────────────────

  test "needs_review bucket = needs_attention + review-needed PR + failed PR statuses" do
    seed_one_per_bucket
    get inbox_path
    counts = controller.instance_variable_get(:@counts)
    assert_equal 4, counts["needs_review"]
  end

  test "agent_working bucket = investigating(no PR) + in-flight PRs, excluding failed" do
    seed_one_per_bucket
    get inbox_path
    counts = controller.instance_variable_get(:@counts)
    assert_equal 2, counts["agent_working"]
  end

  test "shipped bucket = merged PR + resolved-without-PR" do
    seed_one_per_bucket
    get inbox_path
    counts = controller.instance_variable_get(:@counts)
    assert_equal 2, counts["shipped"]
  end

  test "all bucket equals total issues for the project" do
    seed_one_per_bucket
    get inbox_path
    counts = controller.instance_variable_get(:@counts)
    assert_equal Issue.where(project_id: @project.id).count, counts["all"]
  end

  # ── Mutual exclusivity ───────────────────────────────────────────────

  test "buckets are mutually exclusive (no issue counted twice)" do
    seed_one_per_bucket
    # Add an evil case: needs_attention WITH an in-flight PR.
    # Old code would double-count it (needs_review via res_status AND
    # agent_working via auto_fix_status). New code must put it only in
    # needs_review.
    make_issue(resolution_status: "needs_attention", auto_fix_status: "ci_pending", auto_fix_pr_number: 99)

    get inbox_path
    counts = controller.instance_variable_get(:@counts)

    sum = counts["needs_review"] + counts["agent_working"] + counts["shipped"]
    assert sum <= counts["all"], "buckets overlap: needs+working+shipped (#{sum}) > all (#{counts['all']})"
  end

  test "ci_failed lands in needs_review, not agent_working" do
    make_issue(resolution_status: nil, auto_fix_status: "ci_failed", auto_fix_pr_number: 1)
    get inbox_path
    counts = controller.instance_variable_get(:@counts)
    assert_equal 1, counts["needs_review"]
    assert_equal 0, counts["agent_working"]
  end

  test "needs_attention with an in-flight PR is in needs_review only" do
    make_issue(resolution_status: "needs_attention", auto_fix_status: "ci_pending", auto_fix_pr_number: 1)
    get inbox_path
    counts = controller.instance_variable_get(:@counts)
    assert_equal 1, counts["needs_review"]
    assert_equal 0, counts["agent_working"]
  end

  test "merged PR is shipped regardless of resolution_status" do
    make_issue(resolution_status: "investigating", auto_fix_status: "merged", auto_fix_pr_number: 1)
    get inbox_path
    counts = controller.instance_variable_get(:@counts)
    assert_equal 1, counts["shipped"]
    assert_equal 0, counts["agent_working"]
  end

  test "raw issue (no resolution_status, no PR) appears only in all" do
    make_issue(resolution_status: nil, auto_fix_status: nil)
    get inbox_path
    counts = controller.instance_variable_get(:@counts)
    assert_equal 1, counts["all"]
    assert_equal 0, counts["needs_review"]
    assert_equal 0, counts["agent_working"]
    assert_equal 0, counts["shipped"]
  end

  # ── Tab routing ──────────────────────────────────────────────────────

  test "default tab is needs_review" do
    get inbox_path
    assert_equal "needs_review", controller.instance_variable_get(:@active_tab)
  end

  test "tab=agent_working is honored" do
    get inbox_path(tab: "agent_working")
    assert_equal "agent_working", controller.instance_variable_get(:@active_tab)
  end

  test "unknown tab falls back to needs_review" do
    get inbox_path(tab: "garbage")
    assert_equal "needs_review", controller.instance_variable_get(:@active_tab)
  end

  test "tab filter narrows @issues to that bucket only" do
    seed_one_per_bucket
    get inbox_path(tab: "shipped")
    issues = controller.instance_variable_get(:@issues)
    assert_includes issues, @merged
    assert_includes issues, @resolved_nil
    refute_includes issues, @needs_attn
    refute_includes issues, @investigating
  end

  # ── Project scoping ──────────────────────────────────────────────────

  test "scopes to the slug-cookie project when no project_slug in URL" do
    other = projects(:with_slack)
    Issue.create!(account_id: @account.id, project_id: other.id,
                  fingerprint: Digest::SHA256.hexdigest("fp-other"),
                  exception_class: "RuntimeError", top_frame: "x:1",
                  controller_action: "X#y", status: "open", count: 1,
                  first_seen_at: 1.hour.ago, last_seen_at: 5.minutes.ago,
                  resolution_status: "needs_attention")

    make_issue(resolution_status: "needs_attention")

    get inbox_path # cookies[:last_project_slug] = @project.slug from setup
    counts = controller.instance_variable_get(:@counts)
    assert_equal 1, counts["needs_review"], "should only see issues from the cookie-selected project"
  end

  # ── Auto-seed (one-time per project) ─────────────────────────────────

  test "auto-seeds the inbox on first view and marks the project" do
    seed_one_per_bucket
    @project.update!(settings: (@project.settings || {}).except("sre_inbox_seeded_at"))

    queued = []
    AnalyzeIssueJob.stub_any_instance(:perform, ->(*) { }) do
      AnalyzeIssueJob.stub(:perform_async, ->(id) { queued << id }) do
        with_anthropic_key { get inbox_path }
      end
    end

    assert queued.size > 0, "should have queued at least one analysis"
    assert queued.size <= SreInboxController::AUTO_SEED_COUNT, "queues at most AUTO_SEED_COUNT"
    assert @project.reload.settings["sre_inbox_seeded_at"].present?, "should mark project as seeded"
  end

  test "does not re-seed on subsequent views" do
    seed_one_per_bucket
    @project.update!(settings: (@project.settings || {}).merge("sre_inbox_seeded_at" => 1.hour.ago.iso8601))

    queued = []
    AnalyzeIssueJob.stub(:perform_async, ->(id) { queued << id }) do
      with_anthropic_key { get inbox_path }
    end

    assert_empty queued, "must not re-queue when project is already seeded"
  end

  test "does not seed when ANTHROPIC_API_KEY is blank" do
    seed_one_per_bucket
    @project.update!(settings: (@project.settings || {}).except("sre_inbox_seeded_at"))

    queued = []
    AnalyzeIssueJob.stub(:perform_async, ->(id) { queued << id }) do
      with_anthropic_key("") { get inbox_path }
    end

    assert_empty queued
    refute @project.reload.settings.key?("sre_inbox_seeded_at"), "should not mark seeded when no API key"
  end

  # ── Legacy redirects ─────────────────────────────────────────────────

  test "/sre_inbox redirects (301) to /inbox" do
    get "/sre_inbox"
    assert_response :moved_permanently
    assert_equal "/inbox", URI(response.location).path
  end

  test "/sre_inbox2 redirects (301) to /inbox" do
    get "/sre_inbox2"
    assert_response :moved_permanently
    assert_equal "/inbox", URI(response.location).path
  end

  test "/sre_inbox preserves query string on redirect" do
    get "/sre_inbox?tab=shipped"
    assert_response :moved_permanently
    assert_equal "/inbox?tab=shipped", "#{URI(response.location).path}?#{URI(response.location).query}"
  end

  test "/:project_slug/sre_inbox redirects (301) to /inbox and stashes slug" do
    get "/#{@project.slug}/sre_inbox"
    assert_response :moved_permanently
    assert_equal "/inbox", URI(response.location).path
    assert_equal @project.slug, cookies[:last_project_slug]
  end

  test "/:project_slug/sre_inbox2 redirects (301) to /inbox and stashes slug" do
    get "/#{@project.slug}/sre_inbox2"
    assert_response :moved_permanently
    assert_equal "/inbox", URI(response.location).path
    assert_equal @project.slug, cookies[:last_project_slug]
  end

  private

  def with_anthropic_key(value = "sk-test")
    original = ENV["ANTHROPIC_API_KEY"]
    ENV["ANTHROPIC_API_KEY"] = value
    yield
  ensure
    ENV["ANTHROPIC_API_KEY"] = original
  end
end

# Reuse the stub_any_instance shim from analyze_issue_job_test.rb.
unless Class.method_defined?(:stub_any_instance)
  class Class
    def stub_any_instance(method, value_or_lambda)
      original = instance_method(method) rescue nil
      define_method(method) { |*args| value_or_lambda.respond_to?(:call) ? value_or_lambda.call(*args) : value_or_lambda }
      yield
    ensure
      if original
        define_method(method, original)
      else
        remove_method(method) if instance_methods(false).include?(method)
      end
    end
  end
end
