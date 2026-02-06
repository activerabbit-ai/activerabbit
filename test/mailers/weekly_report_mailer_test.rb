require "test_helper"

class WeeklyReportMailerTest < ActionMailer::TestCase
  setup do
    @account = accounts(:default)
    @account.update!(name: "Acme Corp")
    @user = users(:owner)
    @report = {
      period: 7.days.ago..Time.current,
      errors: [],
      performance: []
    }
  end

  test "weekly_report sends to correct recipient" do
    mail = WeeklyReportMailer.with(user: @user, account: @account, report: @report).weekly_report

    assert_equal [@user.email], mail.to
  end

  test "weekly_report includes account name in subject" do
    mail = WeeklyReportMailer.with(user: @user, account: @account, report: @report).weekly_report

    assert_includes mail.subject, "Acme Corp"
  end

  test "weekly_report includes date range in subject" do
    mail = WeeklyReportMailer.with(user: @user, account: @account, report: @report).weekly_report

    assert_includes mail.subject, @report[:period].first.strftime("%B %d, %Y")
    assert_includes mail.subject, @report[:period].last.strftime("%B %d, %Y")
  end

  test "weekly_report formats subject correctly" do
    mail = WeeklyReportMailer.with(user: @user, account: @account, report: @report).weekly_report

    assert_match(/Weekly Report for .+: .+ - .+/, mail.subject)
  end

  test "weekly_report renders the body" do
    mail = WeeklyReportMailer.with(user: @user, account: @account, report: @report).weekly_report

    assert_includes mail.body.encoded, "ActiveRabbit Weekly Report"
  end

  test "weekly_report includes dashboard link" do
    mail = WeeklyReportMailer.with(user: @user, account: @account, report: @report).weekly_report

    assert_includes mail.body.encoded, "Go to Dashboard"
  end

  test "weekly_report shows no errors message when empty" do
    mail = WeeklyReportMailer.with(user: @user, account: @account, report: @report).weekly_report

    assert_includes mail.body.encoded, "No errors recorded this week"
  end

  test "weekly_report shows no performance issues message when empty" do
    mail = WeeklyReportMailer.with(user: @user, account: @account, report: @report).weekly_report

    assert_includes mail.body.encoded, "No performance issues detected"
  end
end
