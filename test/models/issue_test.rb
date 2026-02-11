require "test_helper"

class IssueTest < ActiveSupport::TestCase
  # Validations

  test "validates presence of fingerprint" do
    issue = Issue.new(fingerprint: nil)
    refute issue.valid?
    assert_includes issue.errors[:fingerprint], "can't be blank"
  end

  test "validates presence of exception_class" do
    issue = Issue.new(exception_class: nil)
    refute issue.valid?
    assert_includes issue.errors[:exception_class], "can't be blank"
  end

  test "validates presence of top_frame" do
    issue = Issue.new(top_frame: nil)
    refute issue.valid?
    assert_includes issue.errors[:top_frame], "can't be blank"
  end

  test "validates presence of controller_action" do
    issue = Issue.new(controller_action: nil)
    refute issue.valid?
    assert_includes issue.errors[:controller_action], "can't be blank"
  end

  # find_or_create_by_fingerprint

  test "find_or_create_by_fingerprint creates a new issue and increments counts" do
    project = projects(:default)

    issue = Issue.find_or_create_by_fingerprint(
      project: project,
      exception_class: "RuntimeError",
      top_frame: "/app/controllers/home_controller.rb:10:in `index'",
      controller_action: "HomeController#index",
      sample_message: "boom"
    )

    assert issue.persisted?
    assert_equal 1, issue.count

    # Find same issue again
    same = Issue.find_or_create_by_fingerprint(
      project: project,
      exception_class: "RuntimeError",
      top_frame: "/app/controllers/home_controller.rb:32:in `index'",
      controller_action: "HomeController#index",
      sample_message: "boom again"
    )

    assert_equal issue.id, same.id
    assert_equal 2, same.count
  end

  # Status transitions

  test "mark_wip sets status to wip" do
    issue = issues(:open_issue)
    issue.mark_wip!
    assert_equal "wip", issue.status
  end

  test "close sets status to closed" do
    issue = issues(:open_issue)
    issue.close!
    assert_equal "closed", issue.status
  end

  test "reopen sets status to open" do
    issue = issues(:closed_issue)
    issue.reopen!
    assert_equal "open", issue.status
  end

  # events_last_24h uses occurred_at (not created_at)

  test "events_last_24h counts events by occurred_at" do
    issue = issues(:open_issue)

    # Fixture events for open_issue:
    #   default: occurred_at=now, recent: 5min ago,
    #   recent_event_for_open: 2h ago (all within 24h)
    #   very_old_event_for_open: 3 days ago (outside 24h)
    count = issue.events_last_24h
    assert count >= 2, "Expected at least 2 recent events, got #{count}"

    # The 3-day old event should NOT be counted
    total = issue.events.count
    assert count < total, "events_last_24h should exclude old events"
  end

  test "events_last_24h returns 0 when no recent events" do
    issue = issues(:old_issue)
    # old_issue has no events in fixtures, so count should be 0
    assert_equal 0, issue.events_last_24h
  end

  # Job failure detection heuristic

  test "job failure issue has non-controller controller_action" do
    job_issue = issues(:job_failure_issue)
    refute_match(/Controller#/, job_issue.controller_action)

    regular_issue = issues(:open_issue)
    assert_match(/Controller#/, regular_issue.controller_action)
  end
end
