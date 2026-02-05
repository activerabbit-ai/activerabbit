require 'rails_helper'

RSpec.describe AiPerformanceSummaryService, type: :service do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }
  let(:target) { "UsersController#index" }
  let(:stats) do
    {
      avg_duration: 2500,
      p95_duration: 5000,
      request_count: 100,
      slow_endpoints: [
        { endpoint: "/api/users", avg_duration: 2500, p95_duration: 5000 }
      ]
    }
  end

  before do
    ActsAsTenant.current_tenant = account
  end

  describe '#initialize' do
    it 'accepts target and stats' do
      service = described_class.new(target: target, stats: stats)
      expect(service).to be_a(AiPerformanceSummaryService)
    end

    it 'accepts optional sample_event' do
      event = create(:event, project: project, account: account)
      service = described_class.new(target: target, stats: stats, sample_event: event)
      expect(service).to be_a(AiPerformanceSummaryService)
    end
  end

  describe '#call' do
    context 'when ANTHROPIC_API_KEY is missing' do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
      end

      it 'returns error' do
        service = described_class.new(target: target, stats: stats)
        result = service.call

        expect(result[:error]).to eq("missing_api_key")
      end
    end

    context 'when ANTHROPIC_API_KEY is present' do
      let(:api_response) do
        {
          "content" => [
            {
              "type" => "text",
              "text" => "## Performance Analysis\n\nThe endpoint is slow due to..."
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

      it 'returns performance summary' do
        service = described_class.new(target: target, stats: stats)
        result = service.call

        expect(result[:summary]).to include("Performance Analysis")
      end

      it 'uses claude-opus-4 model' do
        service = described_class.new(target: target, stats: stats)
        service.call

        expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with(body: hash_including("model" => "claude-opus-4-20250514"))
      end

      it 'includes target in request' do
        service = described_class.new(target: target, stats: stats)
        service.call

        expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with { |req| req.body.include?("UsersController#index") }
      end
    end
  end
end
