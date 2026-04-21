require 'rails_helper'

RSpec.describe Account, type: :model do
  subject(:account) { build(:account) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
  end

  describe '#has_any_stats?' do
    context 'when usage data has not been cached yet' do
      it 'returns false' do
        account = create(:account, usage_cached_at: nil)
        expect(account.has_any_stats?).to be false
      end
    end

    context 'when account has events' do
      it 'returns true' do
        account = create(:account,
          cached_events_used: 100,
          cached_performance_events_used: 0,
          cached_ai_summaries_used: 0,
          cached_pull_requests_used: 0,
          usage_cached_at: Time.current
        )
        expect(account.has_any_stats?).to be true
      end
    end

    context 'when account has performance events' do
      it 'returns true' do
        account = create(:account,
          cached_events_used: 0,
          cached_performance_events_used: 50,
          cached_ai_summaries_used: 0,
          cached_pull_requests_used: 0,
          usage_cached_at: Time.current
        )
        expect(account.has_any_stats?).to be true
      end
    end

    context 'when account has AI summaries' do
      it 'returns true' do
        account = create(:account,
          cached_events_used: 0,
          cached_performance_events_used: 0,
          cached_ai_summaries_used: 5,
          cached_pull_requests_used: 0,
          usage_cached_at: Time.current
        )
        expect(account.has_any_stats?).to be true
      end
    end

    context 'when account has pull requests' do
      it 'returns true' do
        account = create(:account,
          cached_events_used: 0,
          cached_performance_events_used: 0,
          cached_ai_summaries_used: 0,
          cached_pull_requests_used: 3,
          usage_cached_at: Time.current
        )
        expect(account.has_any_stats?).to be true
      end
    end

    context 'when account has zero stats' do
      it 'returns false' do
        account = create(:account, :without_stats)
        expect(account.has_any_stats?).to be false
      end
    end
  end

  describe '#ai_provider_config' do
    it 'returns the active AI provider config' do
      account = create(:account)
      config = create(:ai_provider_config, account: account, active: true)

      expect(account.ai_provider_config).to eq(config)
    end

    it 'returns nil when no active config exists' do
      account = create(:account)

      expect(account.ai_provider_config).to be_nil
    end
  end

  describe '#ai_configured?' do
    it 'returns true when an active config exists' do
      account = create(:account)
      create(:ai_provider_config, account: account, active: true)

      expect(account.ai_configured?).to be true
    end

    it 'returns false when no config exists' do
      account = create(:account)

      expect(account.ai_configured?).to be false
    end

    it 'returns true when ANTHROPIC_API_KEY env is set and no DB config' do
      account = create(:account)

      ClimateControl.modify(ANTHROPIC_API_KEY: "sk-ant-test") do
        expect(account.ai_configured?).to be true
      end
    end

    it 'returns true when OPENAI_API_KEY env is set and no DB config' do
      account = create(:account)

      ClimateControl.modify(OPENAI_API_KEY: "sk-test") do
        expect(account.ai_configured?).to be true
      end
    end
  end

  describe '#ai_provider_config ENV fallback' do
    it 'returns ENV-based config when no DB config exists' do
      account = create(:account)

      ClimateControl.modify(ANTHROPIC_API_KEY: "sk-ant-test") do
        config = account.ai_provider_config
        expect(config).to be_present
        expect(config.provider).to eq("anthropic")
        expect(config.api_key).to eq("sk-ant-test")
      end
    end

    it 'prefers DB config over ENV' do
      account = create(:account)
      db_config = create(:ai_provider_config, account: account, provider: "openai", active: true)

      ClimateControl.modify(ANTHROPIC_API_KEY: "sk-ant-test") do
        expect(account.ai_provider_config).to eq(db_config)
      end
    end

    it 'returns nil when neither DB config nor ENV exists' do
      account = create(:account)

      ClimateControl.modify(ANTHROPIC_API_KEY: nil, OPENAI_API_KEY: nil, GEMINI_API_KEY: nil) do
        expect(account.ai_provider_config).to be_nil
      end
    end
  end

  # describe '#slack_channel=' do
  #   it 'normalizes channel to start with #' do
  #     account.slack_channel = 'alerts'
  #     expect(account.slack_channel).to eq('#alerts')
  #   end
  # end

  # describe '#slack_notifications_enabled?' do
  #   it 'is false when not configured' do
  #     allow(account).to receive(:slack_webhook_url).and_return(nil)
  #     expect(account.slack_notifications_enabled?).to eq(false)
  #   end
  # end
end
