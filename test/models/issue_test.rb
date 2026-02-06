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
end
