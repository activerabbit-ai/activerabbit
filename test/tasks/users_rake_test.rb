# frozen_string_literal: true

require "test_helper"
require "rake"

class UsersRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("users:send_confirmation_emails")

    Rake::Task["users:send_confirmation_emails"].reenable
    Rake::Task["users:confirm_all"].reenable

    # Stub stdin to auto-answer "yes" by default
    @original_stdin = $stdin
    $stdin = StringIO.new("yes\n")
  end

  teardown do
    $stdin = @original_stdin
  end

  # Helper to capture stdout
  def capture_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  # users:send_confirmation_emails

  test "send_confirmation_emails finds and processes unconfirmed users" do
    # Use the unconfirmed_user fixture
    unconfirmed = users(:unconfirmed_user)
    # Ensure user is unconfirmed
    unconfirmed.update_columns(confirmed_at: nil, confirmation_sent_at: nil)

    # Count unconfirmed users before
    unconfirmed_count = User.where(confirmed_at: nil).count

    Rake::Task["users:send_confirmation_emails"].reenable
    $stdin = StringIO.new("yes\n")

    output = capture_output do
      Rake::Task["users:send_confirmation_emails"].invoke
    end

    assert_includes output, "Found #{unconfirmed_count} unconfirmed user"
    assert_includes output, unconfirmed.email
  end

  test "send_confirmation_emails does not send when user answers no" do
    # Use fixture
    unconfirmed = users(:unconfirmed_user)
    unconfirmed.update_columns(confirmed_at: nil)

    Rake::Task["users:send_confirmation_emails"].reenable
    $stdin = StringIO.new("no\n")

    initial_count = ActionMailer::Base.deliveries.count

    begin
      capture_output { Rake::Task["users:send_confirmation_emails"].invoke }
    rescue SystemExit
      # Task calls exit on abort
    end

    assert_equal initial_count, ActionMailer::Base.deliveries.count
  end

  # users:confirm_all

  test "confirm_all confirms all unconfirmed users" do
    # Use fixture and ensure it's unconfirmed
    unconfirmed = users(:unconfirmed_user)
    unconfirmed.update_columns(confirmed_at: nil)

    refute unconfirmed.reload.confirmed?

    Rake::Task["users:confirm_all"].reenable
    $stdin = StringIO.new("yes\n")

    capture_output { Rake::Task["users:confirm_all"].invoke }

    assert unconfirmed.reload.confirmed?
  end

  test "confirm_all does not modify already confirmed users" do
    confirmed_user = users(:owner)
    original_confirmed_at = confirmed_user.confirmed_at

    Rake::Task["users:confirm_all"].reenable
    $stdin = StringIO.new("yes\n")

    capture_output { Rake::Task["users:confirm_all"].invoke }

    assert_equal original_confirmed_at.to_i, confirmed_user.reload.confirmed_at.to_i
  end

  test "confirm_all does not send any emails" do
    # Use fixture
    unconfirmed = users(:unconfirmed_user)
    unconfirmed.update_columns(confirmed_at: nil)

    Rake::Task["users:confirm_all"].reenable
    $stdin = StringIO.new("yes\n")

    initial_count = ActionMailer::Base.deliveries.count

    capture_output { Rake::Task["users:confirm_all"].invoke }

    assert_equal initial_count, ActionMailer::Base.deliveries.count
  end
end
