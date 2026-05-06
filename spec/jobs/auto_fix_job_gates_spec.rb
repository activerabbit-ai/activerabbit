require "rails_helper"

RSpec.describe AutoFixJob, "gating" do
  let(:account) { create(:account) }
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      create(:project,
             name: "P",
             environment: "production",
             auto_pr_weekly_cap: 5,
             auto_pr_confidence_threshold: 80,
             settings: { "auto_fix" => { "enabled" => true },
                         "github_repo" => "acme/p",
                         "github_installation_id" => "1" })
    end
  end
  let(:issue) do
    ActsAsTenant.with_tenant(account) do
      create(:issue, project: project, fingerprint: "fp", status: "open",
             ai_summary: "summary", sre_confidence: 90)
    end
  end

  let(:pr_service_double) do
    instance_double(Github::PrService,
      create_pr_for_issue: { success: true, pr_url: "https://github.com/acme/p/pull/1",
                             branch_name: "ai-fix/x", actual_fix_applied: true })
  end

  before do
    allow(Github::PrService).to receive(:new).and_return(pr_service_double)
    allow(Sidekiq).to receive(:redis).and_yield(double(set: true))
  end

  it "marks skipped_no_github when github_installation_id missing" do
    project.update!(settings: project.settings.merge("github_installation_id" => nil))
    AutoFixJob.new.perform(issue.id, project.id)
    expect(issue.reload.auto_fix_status).to eq("skipped_no_github")
    expect(Github::PrService).not_to have_received(:new)
  end

  it "marks skipped_low_confidence when below threshold" do
    issue.update!(sre_confidence: 50)
    AutoFixJob.new.perform(issue.id, project.id)
    expect(issue.reload.auto_fix_status).to eq("skipped_low_confidence")
    expect(Github::PrService).not_to have_received(:new)
  end

  it "marks skipped_capped when 7-day cap hit" do
    5.times do |i|
      ActsAsTenant.with_tenant(account) do
        create(:issue, project: project, fingerprint: "fpc#{i}",
               auto_fix_status: "pr_created",
               auto_fix_attempted_at: i.hours.ago)
      end
    end
    AutoFixJob.new.perform(issue.id, project.id)
    expect(issue.reload.auto_fix_status).to eq("skipped_capped")
    expect(Github::PrService).not_to have_received(:new)
  end

  it "proceeds to PR creation when all gates pass" do
    AutoFixJob.new.perform(issue.id, project.id)
    expect(issue.reload.auto_fix_status).to eq("pr_created")
    expect(Github::PrService).to have_received(:new)
  end

  it "no-op when threshold is 0 (off)" do
    project.update!(auto_pr_confidence_threshold: 0)
    AutoFixJob.new.perform(issue.id, project.id)
    expect(Github::PrService).not_to have_received(:new)
  end
end
