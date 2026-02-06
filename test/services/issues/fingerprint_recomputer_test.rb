require "test_helper"

class Issues::FingerprintRecomputerTest < ActiveSupport::TestCase
  setup do
    @project = projects(:default)
    # Clean up issues for clean test state
    ActsAsTenant.without_tenant do
      Event.delete_all
      Issue.delete_all
    end
  end

  # Old-style fingerprint helper
  def old_style_fingerprint(exception_class, controller_action)
    Digest::SHA256.hexdigest([exception_class, controller_action].join("|"))
  end

  test "merges RecordNotFound issues from same origin into one" do
    # Create issues with OLD fingerprints
    issue1 = Issue.create!(
      account: accounts(:default),
      project: @project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/reports/base_controller.rb:214",
      controller_action: "Reports::HoursController#index",
      fingerprint: old_style_fingerprint("ActiveRecord::RecordNotFound", "Reports::HoursController#index"),
      count: 10,
      first_seen_at: 3.days.ago,
      last_seen_at: 1.day.ago
    )

    issue2 = Issue.create!(
      account: accounts(:default),
      project: @project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/reports/base_controller.rb:214",
      controller_action: "Reports::TasksController#index",
      fingerprint: old_style_fingerprint("ActiveRecord::RecordNotFound", "Reports::TasksController#index"),
      count: 5,
      first_seen_at: 2.days.ago,
      last_seen_at: 12.hours.ago
    )

    stats = Issues::FingerprintRecomputer.new(dry_run: false).call

    assert_equal 1, stats[:merged]

    remaining = Issue.where(project: @project, exception_class: "ActiveRecord::RecordNotFound")
    assert_equal 1, remaining.count
    assert_equal 15, remaining.first.count
  end

  test "does not change issues with correct fingerprints" do
    new_fingerprint = Issue.send(:generate_fingerprint,
      "ActiveRecord::RecordNotFound",
      "app/controllers/users_controller.rb:30",
      "UsersController#show"
    )

    issue = Issue.create!(
      account: accounts(:default),
      project: @project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/users_controller.rb:30",
      controller_action: "UsersController#show",
      fingerprint: new_fingerprint,
      count: 5,
      first_seen_at: 1.day.ago,
      last_seen_at: Time.current
    )

    stats = Issues::FingerprintRecomputer.new(dry_run: false).call

    assert_equal 1, stats[:unchanged]
    assert_equal 0, stats[:merged]
    assert_equal new_fingerprint, issue.reload.fingerprint
  end

  test "dry run mode does not make changes" do
    issue1 = Issue.create!(
      account: accounts(:default),
      project: @project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/base_controller.rb:50",
      controller_action: "UsersController#show",
      fingerprint: "old_fingerprint_1",
      count: 10,
      first_seen_at: 2.days.ago,
      last_seen_at: 1.day.ago
    )

    issue2 = Issue.create!(
      account: accounts(:default),
      project: @project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/base_controller.rb:50",
      controller_action: "ProjectsController#show",
      fingerprint: "old_fingerprint_2",
      count: 5,
      first_seen_at: 1.day.ago,
      last_seen_at: Time.current
    )

    original_count = Issue.count

    stats = Issues::FingerprintRecomputer.new(dry_run: true).call

    assert_equal 1, stats[:merged]
    assert_equal original_count, Issue.count
    assert_equal "old_fingerprint_1", issue1.reload.fingerprint
    assert_equal "old_fingerprint_2", issue2.reload.fingerprint
  end

  test "does not merge issues across different projects" do
    other_project = projects(:secondary)

    issue1 = Issue.create!(
      account: accounts(:default),
      project: @project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/base_controller.rb:50",
      controller_action: "UsersController#show",
      fingerprint: "old_fingerprint_project1",
      count: 10,
      first_seen_at: 2.days.ago,
      last_seen_at: 1.day.ago
    )

    issue2 = Issue.create!(
      account: accounts(:other_account),
      project: other_project,
      exception_class: "ActiveRecord::RecordNotFound",
      top_frame: "app/controllers/base_controller.rb:50",
      controller_action: "UsersController#show",
      fingerprint: "old_fingerprint_project2",
      count: 5,
      first_seen_at: 1.day.ago,
      last_seen_at: Time.current
    )

    stats = Issues::FingerprintRecomputer.new(dry_run: false).call

    assert_equal 2, stats[:updated]
    assert_equal 0, stats[:merged]
    assert Issue.exists?(issue1.id)
    assert Issue.exists?(issue2.id)
  end
end
