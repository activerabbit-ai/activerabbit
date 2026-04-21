require 'rails_helper'

RSpec.describe AiPerformanceSummaryService, type: :service do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }
  let(:target) { "UsersController#index" }
  let(:stats) do
    {
      total_requests: 100,
      total_errors: 5,
      error_rate: 5.0,
      avg_ms: 2500,
      p95_ms: 5000
    }
  end

  before do
    ActsAsTenant.current_tenant = account
  end

  describe '#initialize' do
    it 'accepts account, target, and stats' do
      service = described_class.new(account: account, target: target, stats: stats)
      expect(service).to be_a(AiPerformanceSummaryService)
    end

    it 'accepts optional sample_event' do
      event = create(:event, project: project, account: account)
      service = described_class.new(account: account, target: target, stats: stats, sample_event: event)
      expect(service).to be_a(AiPerformanceSummaryService)
    end
  end

  describe '#call' do
    context 'when no AI provider is configured' do
      it 'returns missing_config error' do
        service = described_class.new(account: account, target: target, stats: stats)
        result = service.call

        expect(result[:error]).to eq("missing_config")
      end
    end

    context 'when AI provider is configured' do
      let!(:ai_config) do
        create(:ai_provider_config,
          account: account,
          provider: "anthropic",
          fast_model: "claude-haiku-4-5-20251001",
          power_model: "claude-sonnet-4-6",
          active: true)
      end

      it 'returns performance summary via RubyLLM' do
        mock_message = double(content: "## Performance Analysis\n\nThe endpoint is slow due to...")
        mock_chat = double(with_instructions: nil)
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_message)
        allow_any_instance_of(described_class).to receive(:ai_chat).and_return(mock_chat)

        service = described_class.new(account: account, target: target, stats: stats)
        result = service.call

        expect(result[:summary]).to include("Performance Analysis")
      end

      it 'uses the fast_model from the active config' do
        mock_message = double(content: "analysis")
        mock_chat = double
        allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
        allow(mock_chat).to receive(:ask).and_return(mock_message)

        mock_ctx = double
        allow(RubyLLM).to receive(:context).and_yield(double.as_null_object).and_return(mock_ctx)
        allow(mock_ctx).to receive(:chat).with(model: "claude-haiku-4-5-20251001").and_return(mock_chat)

        service = described_class.new(account: account, target: target, stats: stats)
        result = service.call

        expect(result[:summary]).to eq("analysis")
      end
    end
  end
end
