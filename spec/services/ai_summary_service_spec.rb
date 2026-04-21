require 'rails_helper'

RSpec.describe AiSummaryService, type: :service do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account, settings: { "github_repo" => "owner/repo" }) }
  let(:issue) { create(:issue, project: project, account: account, exception_class: "NoMethodError", sample_message: "undefined method `foo' for nil:NilClass") }
  let(:event) do
    create(:event,
      project: project,
      account: account,
      issue: issue,
      exception_class: "NoMethodError",
      message: "undefined method `foo' for nil:NilClass",
      backtrace: ["/app/controllers/users_controller.rb:25:in `show'"],
      context: {
        "structured_stack_trace" => [
          {
            "file" => "app/controllers/users_controller.rb",
            "line" => 25,
            "method" => "show",
            "in_app" => true,
            "source_context" => {
              "lines_before" => ["  def show", "    @user = User.find(params[:id])"],
              "line_content" => "    @user.foo",
              "lines_after" => ["  end"]
            }
          }
        ]
      }
    )
  end

  before do
    ActsAsTenant.current_tenant = account
  end

  describe '#initialize' do
    it 'accepts issue and sample_event' do
      service = described_class.new(account: account, issue: issue, sample_event: event)
      expect(service).to be_a(AiSummaryService)
    end

    it 'accepts optional github_client' do
      github_client = double("GithubClient")
      service = described_class.new(account: account, issue: issue, sample_event: event, github_client: github_client)
      expect(service).to be_a(AiSummaryService)
    end
  end

  describe '#call' do
    context 'when no AI provider is configured' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
        allow(ENV).to receive(:[]).with("GEMINI_API_KEY").and_return(nil)
      end

      it 'returns missing_config error' do
        service = described_class.new(account: account, issue: issue, sample_event: event)
        result = service.call

        expect(result[:error]).to eq("missing_config")
      end
    end

    context 'when AI provider is configured' do
      let!(:ai_config) { create(:ai_provider_config, account: account, active: true) }

      let(:summary_text) { "## Root Cause\n\nThe error occurs because...\n\n## Fix\n\n**Before:**\n\n```ruby\n@user.foo\n```\n\n**After:**\n\n```ruby\n@user&.foo\n```\n\n## Prevention\n\nUse safe navigation." }

      before do
        mock_message = double(content: summary_text)
        mock_chat = double
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_message)
        allow_any_instance_of(described_class).to receive(:ai_chat).and_return(mock_chat)
      end

      it 'returns AI summary' do
        service = described_class.new(account: account, issue: issue, sample_event: event)
        result = service.call

        expect(result[:summary]).to include("Root Cause")
        expect(result[:summary]).to include("Fix")
      end

      it 'includes error details in prompt' do
        mock_chat = double
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:ask) do |content|
          expect(content).to include("NoMethodError")
          double(content: summary_text)
        end
        allow_any_instance_of(described_class).to receive(:ai_chat).and_return(mock_chat)

        service = described_class.new(account: account, issue: issue, sample_event: event)
        service.call
      end
    end

    context 'when AI call raises error' do
      let!(:ai_config) { create(:ai_provider_config, account: account, active: true) }

      before do
        mock_chat = double
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_raise(RuntimeError, "API error")
        allow_any_instance_of(described_class).to receive(:ai_chat).and_return(mock_chat)
      end

      it 'returns ai_error' do
        service = described_class.new(account: account, issue: issue, sample_event: event)
        result = service.call

        expect(result[:error]).to eq("ai_error")
      end
    end

    context 'with GitHub client for fetching related files' do
      let(:github_client) { double("GithubClient") }
      let!(:ai_config) { create(:ai_provider_config, account: account, active: true) }

      before do
        mock_message = double(content: "## Root Cause\n\nTest")
        mock_chat = double
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_message)
        allow_any_instance_of(described_class).to receive(:ai_chat).and_return(mock_chat)
      end

      it 'fetches full error file from GitHub when client provided' do
        controller_content = Base64.encode64("class UsersController < ApplicationController\n  def show\n    @user = User.find(params[:id])\n    @user.foo\n  end\nend")
        model_content = Base64.encode64("class User < ApplicationRecord\n  validates :name, presence: true\nend")

        allow(github_client).to receive(:get).and_return(nil)
        allow(github_client).to receive(:get)
          .with("/repos/owner/repo/contents/app/controllers/users_controller.rb")
          .and_return({ "content" => controller_content })
        allow(github_client).to receive(:get)
          .with("/repos/owner/repo/contents/app/models/user.rb")
          .and_return({ "content" => model_content })

        service = described_class.new(account: account, issue: issue, sample_event: event, github_client: github_client)
        result = service.call

        expect(result[:summary]).to be_present
      end
    end
  end

  describe 'SYSTEM_PROMPT' do
    it 'includes required format instructions' do
      expect(AiSummaryService::SYSTEM_PROMPT).to include("## Root Cause")
      expect(AiSummaryService::SYSTEM_PROMPT).to include("## Suggested Fix")
      expect(AiSummaryService::SYSTEM_PROMPT).to include("## Prevention")
    end

    it 'requires precise fix format with file and line' do
      expect(AiSummaryService::SYSTEM_PROMPT).to include("### File 1:")
      expect(AiSummaryService::SYSTEM_PROMPT).to include("**Line:**")
    end

    it 'mentions Related Changes for multi-file scenarios' do
      expect(AiSummaryService::SYSTEM_PROMPT).to include("Related Changes")
      expect(AiSummaryService::SYSTEM_PROMPT).to include("fix locally")
    end
  end
end
