require 'rails_helper'

RSpec.describe PerfRollup, type: :model do
  let(:project) { create(:project) }

  describe '.rollup_minute_data!' do
    it 'creates rollups from recent performance events' do
      now = Time.current.change(sec: 0)
      # events from 2 minutes ago window
      t1 = now - 90.seconds
      create(:performance_event, project: project, occurred_at: t1, duration_ms: 200)
      create(:performance_event, project: project, occurred_at: t1 + 5.seconds, duration_ms: 400)

      expect {
        described_class.rollup_minute_data!
      }.to change { described_class.count }.by(1)

      rollup = described_class.last
      expect(rollup.project).to eq(project)
      expect(rollup.timeframe).to eq('minute')
      expect(rollup.request_count).to be >= 2
      expect(rollup.avg_duration_ms).to be_between(200, 400)
    end
  end
end
