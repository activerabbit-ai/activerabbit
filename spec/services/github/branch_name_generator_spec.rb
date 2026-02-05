require 'rails_helper'

RSpec.describe Github::BranchNameGenerator, type: :service do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }
  let(:issue) do
    create(:issue,
      project: project,
      account: account,
      exception_class: "NoMethodError",
      sample_message: "undefined method `foo' for nil:NilClass",
      controller_action: "UsersController#show"
    )
  end

  let(:service) { described_class.new(anthropic_key: "test-key") }

  before do
    ActsAsTenant.current_tenant = account
  end

  describe '#initialize' do
    it 'accepts anthropic_key' do
      service = described_class.new(anthropic_key: "test-key")
      expect(service).to be_a(Github::BranchNameGenerator)
    end
  end

  describe '#generate' do
    context 'with custom branch name' do
      it 'returns sanitized custom branch name with prefix' do
        result = service.generate(issue, "my-custom-branch")

        # Service adds ai-fix/ prefix if no prefix present
        expect(result).to eq("ai-fix/my-custom-branch")
      end

      it 'sanitizes invalid characters' do
        result = service.generate(issue, "My Branch Name!")

        expect(result).to eq("ai-fix/my-branch-name")
      end

      it 'handles spaces and special characters' do
        result = service.generate(issue, "fix: user login issue")

        expect(result).not_to include(" ")
        expect(result).not_to include(":")
      end

      it 'preserves existing prefix' do
        result = service.generate(issue, "fix/my-branch")

        expect(result).to eq("fix/my-branch")
      end
    end

    context 'with AI generation' do
      let(:api_response) do
        {
          "content" => [
            {
              "type" => "text",
              "text" => "ai-fix/nomethoderror-users-show"
            }
          ]
        }
      end

      before do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(status: 200, body: api_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'generates branch name via AI' do
        result = service.generate(issue)

        expect(result).to be_present
        expect(result).to match(/^ai-fix\//)
      end

      it 'uses claude-opus-4 model' do
        service.generate(issue)

        expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with(body: hash_including("model" => "claude-opus-4-20250514"))
      end

      it 'includes issue details in prompt' do
        service.generate(issue)

        expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with { |req| req.body.include?("NoMethodError") }
      end
    end

    context 'without AI (fallback)' do
      let(:service) { described_class.new(anthropic_key: nil) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
      end

      it 'generates fallback branch name' do
        result = service.generate(issue)

        expect(result).to be_present
        expect(result).to start_with("ai-fix/")
        expect(result).to include("no-method") # From NoMethodError
      end
    end

    context 'when AI fails' do
      before do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(status: 500, body: "Internal Server Error")
      end

      it 'falls back to generated name' do
        result = service.generate(issue)

        expect(result).to be_present
        expect(result).to include("fix")
      end
    end
  end

  describe 'branch name format' do
    let(:api_response) do
      {
        "content" => [
            {
              "type" => "text",
              "text" => "ai-fix/nomethoderror-users-show"
            }
          ]
      }
    end

    before do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 200, body: api_response.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'produces valid git branch name' do
      result = service.generate(issue)

      # Git branch name rules
      expect(result).not_to start_with("-")
      expect(result).not_to end_with("-")
      expect(result).not_to include(" ")
      expect(result).not_to include("..")
      expect(result).to match(/^[a-z0-9\-\/]+$/i)
    end

    it 'is reasonably short' do
      result = service.generate(issue)

      expect(result.length).to be <= 100
    end
  end
end
