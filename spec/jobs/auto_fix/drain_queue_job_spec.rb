require "rails_helper"

RSpec.describe AutoFix::DrainQueueJob do
  let(:account) { create(:account) }
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      create(:project, name: "P", environment: "production",
             auto_pr_weekly_cap: 5,
             settings: { "github_installation_id" => "1",
                         "auto_fix" => { "enabled" => true } })
    end
  end

  it "re-enqueues oldest skipped_capped issue when cap window has opened" do
    queued = ActsAsTenant.with_tenant(account) do
      create(:issue, project: project, fingerprint: "old",
             ai_summary: "s", auto_fix_status: "skipped_capped")
    end
    # 5 PRs all >7 days old → cap window is open
    5.times do |i|
      ActsAsTenant.with_tenant(account) do
        create(:issue, project: project, fingerprint: "fpc#{i}",
               auto_fix_status: "pr_created",
               auto_fix_attempted_at: 8.days.ago - i.hours)
      end
    end
    expect(AutoFixJob).to receive(:perform_async).with(queued.id, project.id)
    described_class.perform_now
    expect(queued.reload.auto_fix_status).to be_nil
  end

  it "does NOT re-enqueue when cap is still hit" do
    queued = ActsAsTenant.with_tenant(account) do
      create(:issue, project: project, fingerprint: "old",
             ai_summary: "s", auto_fix_status: "skipped_capped")
    end
    # 5 PRs within 7 days = cap full
    5.times do |i|
      ActsAsTenant.with_tenant(account) do
        create(:issue, project: project, fingerprint: "fpc#{i}",
               auto_fix_status: "pr_created",
               auto_fix_attempted_at: i.hours.ago)
      end
    end
    expect(AutoFixJob).not_to receive(:perform_async)
    described_class.perform_now
    expect(queued.reload.auto_fix_status).to eq("skipped_capped")
  end
end
