# frozen_string_literal: true

require "test_helper"
require "rake"

class IssuesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("issues:recompute_fingerprints")
    @account = accounts(:default)
    @project = projects(:default)
    ActsAsTenant.current_tenant = @account

    Rake::Task["issues:recompute_fingerprints"].reenable
    Rake::Task["issues:preview_fingerprint_changes"].reenable
  end

  # Helper to capture stdout
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  # issues:recompute_fingerprints

  test "runs in dry_run mode by default when passed true" do
    issue = Issue.create!(
      project: @project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/base.rb:50",
      controller_action: "UsersController#show",
      fingerprint: "old_fingerprint",
      count: 5,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    original_fingerprint = issue.fingerprint

    output = capture_stdout do
      Rake::Task["issues:recompute_fingerprints"].invoke("true")
    end

    assert_includes output, "DRY RUN"
    assert_equal original_fingerprint, issue.reload.fingerprint
  end

  test "applies changes when dry_run is false" do
    issue = Issue.create!(
      project: @project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/base.rb:50",
      controller_action: "UsersController#show",
      fingerprint: "old_fingerprint",
      count: 5,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    Rake::Task["issues:recompute_fingerprints"].reenable

    output = capture_stdout do
      Rake::Task["issues:recompute_fingerprints"].invoke("false")
    end

    assert_includes output, "Updating fingerprint"

    expected_fingerprint = Issue.send(:generate_fingerprint,
      "ActiveRecord::RecordNotFound",
      "app/controllers/base.rb:50",
      "UsersController#show"
    )

    assert_equal expected_fingerprint, issue.reload.fingerprint
  end

  test "outputs summary statistics" do
    Issue.create!(
      project: @project,
      exception_class: "RuntimeError",
      top_frame: "app/test.rb:1",
      controller_action: "TestController#action",
      fingerprint: "needs_update",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    output = capture_stdout do
      Rake::Task["issues:recompute_fingerprints"].invoke("true")
    end

    assert_includes output, "Issue Fingerprint Recomputation"
    assert_includes output, "Issues processed:"
    assert_includes output, "Issues merged:"
    assert_includes output, "Issues updated:"
    assert_includes output, "Summary"
  end

  test "respects DRY_RUN environment variable" do
    issue = Issue.create!(
      project: @project,
      exception_class: "RuntimeError",
      top_frame: "app/test.rb:1",
      controller_action: "TestController#action",
      fingerprint: "old_fp",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    original_fp = issue.fingerprint

    ClimateControl.modify(DRY_RUN: "true") do
      Rake::Task["issues:recompute_fingerprints"].reenable
      capture_stdout { Rake::Task["issues:recompute_fingerprints"].invoke }
    end

    assert_equal original_fp, issue.reload.fingerprint
  end

  # issues:preview_fingerprint_changes

  test "preview_fingerprint_changes is an alias for dry run mode" do
    issue = Issue.create!(
      project: @project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/base.rb:50",
      controller_action: "UsersController#show",
      fingerprint: "old_fingerprint",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    original_fingerprint = issue.fingerprint

    output = capture_stdout do
      Rake::Task["issues:preview_fingerprint_changes"].invoke
    end

    assert_includes output, "DRY RUN"
    assert_equal original_fingerprint, issue.reload.fingerprint
  end
end
