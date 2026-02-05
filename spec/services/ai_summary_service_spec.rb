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
      service = described_class.new(issue: issue, sample_event: event)
      expect(service).to be_a(AiSummaryService)
    end

    it 'accepts optional github_client' do
      github_client = double("GithubClient")
      service = described_class.new(issue: issue, sample_event: event, github_client: github_client)
      expect(service).to be_a(AiSummaryService)
    end
  end

  describe '#call' do
    context 'when ANTHROPIC_API_KEY is missing' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
      end

      it 'returns missing_api_key error' do
        service = described_class.new(issue: issue, sample_event: event)
        result = service.call

        expect(result[:error]).to eq("missing_api_key")
        expect(result[:message]).to include("ANTHROPIC_API_KEY")
      end
    end

    context 'when ANTHROPIC_API_KEY is present' do
      let(:api_response) do
        {
          "content" => [
            {
              "type" => "text",
              "text" => "## Root Cause\n\nThe error occurs because...\n\n## Fix\n\n**Before:**\n\n```ruby\n@user.foo\n```\n\n**After:**\n\n```ruby\n@user&.foo\n```\n\n## Prevention\n\nUse safe navigation."
            }
          ]
        }
      end

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("test-api-key")

        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(
            status: 200,
            body: api_response.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns AI summary' do
        service = described_class.new(issue: issue, sample_event: event)
        result = service.call

        expect(result[:summary]).to include("Root Cause")
        expect(result[:summary]).to include("Fix")
      end

      it 'sends correct request to Anthropic API' do
        service = described_class.new(issue: issue, sample_event: event)
        service.call

        expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with(
            headers: {
              'x-api-key' => 'test-api-key',
              'anthropic-version' => '2023-06-01',
              'Content-Type' => 'application/json'
            }
          )
      end

      it 'uses claude-opus-4 model' do
        service = described_class.new(issue: issue, sample_event: event)
        service.call

        expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with(body: hash_including("model" => "claude-opus-4-20250514"))
      end

      it 'uses max_tokens of 5000' do
        service = described_class.new(issue: issue, sample_event: event)
        service.call

        expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with(body: hash_including("max_tokens" => 5000))
      end

      it 'includes error details in request' do
        service = described_class.new(issue: issue, sample_event: event)
        service.call

        expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with { |req| req.body.include?("NoMethodError") }
      end
    end

    context 'when API returns error' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("test-api-key")

        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(status: 500, body: "Internal Server Error")
      end

      it 'returns ai_error' do
        service = described_class.new(issue: issue, sample_event: event)
        result = service.call

        expect(result[:error]).to eq("ai_error")
      end
    end

    context 'with GitHub client for fetching related files' do
      let(:github_client) { double("GithubClient") }
      let(:api_response) do
        {
          "content" => [{ "type" => "text", "text" => "## Root Cause\n\nTest" }]
        }
      end

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("test-api-key")

        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(status: 200, body: api_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'fetches full error file from GitHub when client provided' do
        controller_content = Base64.encode64("class UsersController < ApplicationController\n  def show\n    @user = User.find(params[:id])\n    @user.foo\n  end\nend")
        model_content = Base64.encode64("class User < ApplicationRecord\n  validates :name, presence: true\nend")

        # Stub all potential GitHub API calls
        allow(github_client).to receive(:get).and_return(nil)
        allow(github_client).to receive(:get)
          .with("/repos/owner/repo/contents/app/controllers/users_controller.rb")
          .and_return({ "content" => controller_content })
        allow(github_client).to receive(:get)
          .with("/repos/owner/repo/contents/app/models/user.rb")
          .and_return({ "content" => model_content })

        service = described_class.new(issue: issue, sample_event: event, github_client: github_client)
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
