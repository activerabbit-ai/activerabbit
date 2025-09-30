require 'rails_helper'

RSpec.describe OverageCalculator do
  let(:account) { create(:account, current_plan: 'developer') }

  before do
    # Create some daily counts
    DailyEventCount.create!(account: account, day: Date.current, count: 60_000)
  end

  it 'computes overage above quota' do
    calc = described_class.new(account: account)
    start_time = Time.current.beginning_of_month
    end_time = Time.current.end_of_month
    expect(calc.overage_events(period_start: start_time, period_end: end_time)).to be >= 10_000
  end

  it 'uses enterprise quota when plan is enterprise' do
    account.update!(current_plan: 'enterprise')
    calc = described_class.new(account: account)
    start_time = Date.current.beginning_of_month.to_time
    end_time = Date.current.end_of_month.to_time
    expect(calc.quota_for_account).to be >= 2_000_000
  end
end
