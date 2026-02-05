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
