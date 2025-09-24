require 'rails_helper'

RSpec.describe PerformanceEvent, type: :model do
  let(:project) { create(:project) }

  describe '.ingest_performance' do
    it 'creates a performance event' do
      payload = {
        controller_action: 'HomeController#index',
        duration_ms: 250.5,
        db_duration_ms: 80.1,
        view_duration_ms: 120.2,
        occurred_at: Time.current.iso8601,
        environment: 'production'
      }

      expect {
        described_class.ingest_performance(project: project, payload: payload)
      }.to change { described_class.count }.by(1)
    end
  end

  describe '#slow? and #very_slow?' do
    it 'returns booleans based on thresholds' do
      fast = build(:performance_event, duration_ms: 200)
      slow = build(:performance_event, duration_ms: 1500)
      very_slow = build(:performance_event, duration_ms: 6000)

      expect(fast.slow?).to eq(false)
      expect(slow.slow?).to eq(true)
      expect(very_slow.very_slow?).to eq(true)
    end
  end
end


