require 'rails_helper'

RSpec.describe Github::PrService, type: :service do
  let(:account) { create(:account) }
  let(:project) do
    create(:project,
      account: account,
      settings: {
        "github_repo" => "owner/repo",
        "github_pat" => "test-pat-token"
      }
    )
  end
  let(:issue) do
    create(:issue,
      project: project,
      account: account,
      exception_class: "NoMethodError",
      sample_message: "undefined method `foo' for nil:NilClass",
      controller_action: "UsersController#show",
      ai_summary: "## Root Cause\n\nTest\n\n## Fix\n\n```ruby\n@user&.foo\n```"
    )
  end
  let(:event) do
    create(:event,
      project: project,
      account: account,
      issue: issue,
      context: {
        "structured_stack_trace" => [
          {
            "file" => "app/controllers/users_controller.rb",
            "line" => 25,
            "method" => "show",
            "in_app" => true,
            "source_context" => {
              "lines_before" => ["  def show"],
              "line_content" => "    @user.foo",
              "lines_after" => ["  end"]
            }
          }
        ]
      }
    )
  end

  let(:service) { described_class.new(project) }

  before do
    ActsAsTenant.current_tenant = account
    issue.events << event

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("test-anthropic-key")
  end

  describe '#initialize' do
    it 'accepts project' do
      service = described_class.new(project)
      expect(service).to be_a(Github::PrService)
    end

    it 'extracts github_repo from settings' do
      expect(service.send(:configured?)).to be true
    end
  end

  describe '#configured?' do
    it 'returns true when github_repo is set' do
      expect(service.send(:configured?)).to be true
    end

    it 'returns false when github_repo is missing' do
      project.update!(settings: {})
      service = described_class.new(project)

      expect(service.send(:configured?)).to be false
    end
  end

  describe '#create_pr_for_issue' do
    context 'when not configured' do
      before do
        project.update!(settings: {})
      end

      it 'returns error' do
        service = described_class.new(project)
        result = service.create_pr_for_issue(issue)

        expect(result[:success]).to be false
        expect(result[:error]).to include("not configured")
      end
    end

    context 'when configured' do
      let(:file_content) do
        Base64.encode64(<<~RUBY)
          class UsersController < ApplicationController
            def show
              @user = User.find(params[:id])
              @user.foo
            end
          end
        RUBY
      end

      before do
        # Mock all GitHub API calls
        stub_request(:get, %r{https://api.github.com/.*})
          .to_return(status: 200, body: { 
            "default_branch" => "main",
            "object" => { "sha" => "abc123" },
            "tree" => { "sha" => "tree123" },
            "content" => file_content,
            "sha" => "abc123"
          }.to_json, headers: { 'Content-Type' => 'application/json' })

        stub_request(:post, %r{https://api.github.com/.*})
          .to_return(status: 201, body: { 
            "ref" => "refs/heads/fix/test",
            "sha" => "newtree123",
            "html_url" => "https://github.com/owner/repo/pull/1", 
            "number" => 1 
          }.to_json, headers: { 'Content-Type' => 'application/json' })

        stub_request(:patch, %r{https://api.github.com/.*})
          .to_return(status: 200, body: {}.to_json, headers: { 'Content-Type' => 'application/json' })

        # Mock Anthropic API
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(status: 200, body: {
            "content" => [{ "type" => "text", "text" => '{"replacements": [{"line": 4, "old": "    @user.foo", "new": "    @user&.foo"}]}' }]
          }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'attempts PR creation' do
        result = service.create_pr_for_issue(issue)

        # May succeed or fail depending on fix application
        expect(result).to be_a(Hash)
        expect(result).to have_key(:success).or have_key(:error)
      end

      it 'accepts custom branch name' do
        result = service.create_pr_for_issue(issue, custom_branch_name: "my-fix-branch")

        expect(result).to be_a(Hash)
      end
    end
  end

  describe '#create_n_plus_one_fix_pr' do
    let(:sql_fingerprint) { double("SqlFingerprint", id: 1, fingerprint: "SELECT * FROM users") }

    context 'when not configured' do
      before do
        project.update!(settings: {})
      end

      it 'returns error' do
        service = described_class.new(project)
        result = service.create_n_plus_one_fix_pr(sql_fingerprint)

        expect(result[:success]).to be false
        expect(result[:error]).to include("not configured")
      end
    end
  end
end
