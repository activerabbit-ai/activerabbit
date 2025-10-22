require 'rails_helper'

RSpec.describe Event, type: :model do
  let(:project) { create(:project) }

  describe '.ingest_error' do
    it 'creates an issue and an event' do
      payload = {
        exception_class: 'ArgumentError',
        message: 'bad arg',
        backtrace: ["/app/controllers/example_controller.rb:5:in `show'"],
        request_path: '/example',
        request_method: 'GET',
        environment: 'production',
        occurred_at: Time.current.iso8601
      }

      expect {
        Event.ingest_error(project: project, payload: payload)
      }.to change { Issue.count }.by(1).and change { Event.count }.by(1)
    end
  end

  describe '#top_frame and #formatted_backtrace' do
    it 'extracts top frame and formats backtrace' do
      event = build(:event)
      expect(event.top_frame).to be_present
      expect(event.formatted_backtrace).to be_an(Array)
    end
  end
end

