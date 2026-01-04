require 'rails_helper'

RSpec.describe WeeklyReportMailer, type: :mailer do
  let(:account) { create(:account, name: "Acme Corp") }
  let(:user) { create(:user, account: account, email: "user@example.com") }
  let(:report) do
    {
      period: 7.days.ago..Time.current,
      errors: [],
      performance: []
    }
  end

  describe "#weekly_report" do
    let(:mail) do
      described_class.with(user: user, account: account, report: report).weekly_report
    end

    it "sends to the correct recipient" do
      expect(mail.to).to eq(["user@example.com"])
    end

    it "includes account name in subject" do
      expect(mail.subject).to include("Acme Corp")
    end

    it "includes date range in subject" do
      expect(mail.subject).to include(report[:period].first.strftime("%B %d, %Y"))
      expect(mail.subject).to include(report[:period].last.strftime("%B %d, %Y"))
    end

    it "formats subject correctly" do
      # Example: "Weekly Report for Acme Corp: January 01, 2026 - January 08, 2026"
      expect(mail.subject).to match(/Weekly Report for .+: .+ - .+/)
    end

    it "renders the body" do
      expect(mail.body.encoded).to include("ActiveRabbit Weekly Report")
    end

    it "includes dashboard link" do
      expect(mail.body.encoded).to include("Go to Dashboard")
    end

    context "with no errors" do
      let(:report) do
        {
          period: 7.days.ago..Time.current,
          errors: [],
          performance: []
        }
      end

      it "shows no errors message" do
        expect(mail.body.encoded).to include("No errors recorded this week")
      end
    end

    context "with no performance issues" do
      let(:report) do
        {
          period: 7.days.ago..Time.current,
          errors: [],
          performance: []
        }
      end

      it "shows no performance issues message" do
        expect(mail.body.encoded).to include("No performance issues detected")
      end
    end
  end
end
