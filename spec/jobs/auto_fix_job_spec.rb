require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe AutoFixJob, type: :job do
  let(:account) { create(:account) }
  let(:project) do
    create(:project, account: account, settings: {
      "github_repo" => "owner/repo",
      "github_pat" => "ghp_test",
      "github_installation_id" => "1",
      "auto_fix" => { "enabled" => true, "auto_merge" => false, "min_severity" => "low" }
    })
  end
  let(:issue) do
    create(:issue, project: project, account: account,
           status: "open", ai_summary: "## Root Cause\nBug\n## Fix\n```ruby\nfix\n```",
           sre_confidence: 90)
  end

  before do
    ActsAsTenant.current_tenant = account
    Sidekiq::Testing.fake!
    Sidekiq::Worker.clear_all

    allow(Sidekiq).to receive(:redis).and_yield(MockRedis.new)
  end

  class MockRedis
    def initialize; @data = {}; end
    def set(key, value, nx: false, ex: nil)
      return false if nx && @data.key?(key)
      @data[key] = value
      true
    end
  end

  describe '#perform' do
    context 'when issue is eligible' do
      it 'creates a PR and updates issue status' do
        pr_service = instance_double(Github::PrService)
        allow(Github::PrService).to receive(:new).and_return(pr_service)
        allow(pr_service).to receive(:create_pr_for_issue).and_return({
          success: true,
          pr_url: "https://github.com/owner/repo/pull/99",
          branch_name: "ai-fix/test-branch",
          actual_fix_applied: true
        })

        described_class.new.perform(issue.id, project.id)
        issue.reload

        expect(issue.auto_fix_status).to eq("pr_created")
        expect(issue.auto_fix_pr_url).to eq("https://github.com/owner/repo/pull/99")
        expect(issue.auto_fix_pr_number).to eq(99)
        expect(issue.auto_fix_branch).to eq("ai-fix/test-branch")
      end

      it 'sets review_needed status when fix not applied' do
        pr_service = instance_double(Github::PrService)
        allow(Github::PrService).to receive(:new).and_return(pr_service)
        allow(pr_service).to receive(:create_pr_for_issue).and_return({
          success: true,
          pr_url: "https://github.com/owner/repo/pull/100",
          branch_name: "ai-fix/test-branch",
          actual_fix_applied: false
        })

        described_class.new.perform(issue.id, project.id)
        issue.reload

        expect(issue.auto_fix_status).to eq("pr_created_review_needed")
      end

      it 'sets failed status on PR creation failure' do
        pr_service = instance_double(Github::PrService)
        allow(Github::PrService).to receive(:new).and_return(pr_service)
        allow(pr_service).to receive(:create_pr_for_issue).and_return({
          success: false, error: "Branch not found"
        })

        described_class.new.perform(issue.id, project.id)
        issue.reload

        expect(issue.auto_fix_status).to eq("failed")
        expect(issue.auto_fix_error).to eq("Branch not found")
      end

      it 'schedules AutoFixMonitorJob when auto_merge is enabled' do
        project.update!(settings: project.settings.merge(
          "auto_fix" => { "enabled" => true, "auto_merge" => true }
        ))

        pr_service = instance_double(Github::PrService)
        allow(Github::PrService).to receive(:new).and_return(pr_service)
        allow(pr_service).to receive(:create_pr_for_issue).and_return({
          success: true,
          pr_url: "https://github.com/owner/repo/pull/99",
          branch_name: "ai-fix/test-branch",
          actual_fix_applied: true
        })

        described_class.new.perform(issue.id, project.id)

        expect(AutoFixMonitorJob.jobs.size).to eq(1)
      end
    end

    context 'when issue is not eligible' do
      it 'skips closed issues' do
        issue.update_columns(status: "closed")
        expect(Github::PrService).not_to receive(:new)
        described_class.new.perform(issue.id, project.id)
      end

      it 'skips issues without ai_summary' do
        issue.update_columns(ai_summary: nil)
        expect(Github::PrService).not_to receive(:new)
        described_class.new.perform(issue.id, project.id)
      end

      it 'skips issues that already have auto_fix_status' do
        issue.update_columns(auto_fix_status: "pr_created")
        expect(Github::PrService).not_to receive(:new)
        described_class.new.perform(issue.id, project.id)
      end

      it 'skips when auto_fix is disabled on project' do
        project.update!(settings: project.settings.merge("auto_fix" => { "enabled" => false }))
        expect(Github::PrService).not_to receive(:new)
        described_class.new.perform(issue.id, project.id)
      end
    end
  end
end
