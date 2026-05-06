require "rails_helper"

RSpec.describe SreInbox::Analyzer, "auto-fix re-trigger" do
  let(:account) { create(:account) }
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      create(:project, name: "P", environment: "production",
             auto_pr_confidence_threshold: 80,
             settings: { "auto_fix" => { "enabled" => true },
                         "github_repo" => "x/y",
                         "github_installation_id" => "1" })
    end
  end

  it "re-enqueues AutoFixJob when previously-skipped issue now meets threshold" do
    issue = ActsAsTenant.with_tenant(account) do
      create(:issue, project: project, fingerprint: "fp",
             ai_summary: "ok",
             auto_fix_status: "skipped_low_confidence",
             sre_confidence: 50)
    end

    analyzer = described_class.new(issue)
    expect(AutoFixJob).to receive(:perform_async).with(issue.id, project.id)

    analyzer.send(:persist!, { "resolution_status" => "open", "confidence" => 90 })
    expect(issue.reload.auto_fix_status).to be_nil
  end

  it "does NOT re-enqueue if confidence stays below threshold" do
    issue = ActsAsTenant.with_tenant(account) do
      create(:issue, project: project, fingerprint: "fp2",
             ai_summary: "ok",
             auto_fix_status: "skipped_low_confidence",
             sre_confidence: 50)
    end

    analyzer = described_class.new(issue)
    expect(AutoFixJob).not_to receive(:perform_async)

    analyzer.send(:persist!, { "resolution_status" => "open", "confidence" => 60 })
    expect(issue.reload.auto_fix_status).to eq("skipped_low_confidence")
  end

  it "does NOT re-enqueue if issue isn't in skipped_low_confidence state" do
    issue = ActsAsTenant.with_tenant(account) do
      create(:issue, project: project, fingerprint: "fp3",
             ai_summary: "ok",
             auto_fix_status: nil,
             sre_confidence: 50)
    end

    analyzer = described_class.new(issue)
    expect(AutoFixJob).not_to receive(:perform_async)

    analyzer.send(:persist!, { "resolution_status" => "open", "confidence" => 90 })
  end
end
