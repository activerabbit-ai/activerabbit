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

    it 'stores structured_stack_trace in context' do
      structured_frames = [
        {
          file: "app/controllers/users_controller.rb",
          line: 25,
          method: "show",
          in_app: true,
          frame_type: :controller,
          source_context: {
            lines_before: ["  def show", "    @user = User.find(params[:id])"],
            line_content: "    raise 'Not found'",
            lines_after: ["  end"],
            start_line: 23
          }
        }
      ]

      payload = {
        exception_class: 'ArgumentError',
        message: 'test error',
        backtrace: ["app/controllers/users_controller.rb:25:in `show'"],
        structured_stack_trace: structured_frames,
        culprit_frame: structured_frames.first,
        occurred_at: Time.current.iso8601
      }

      event = Event.ingest_error(project: project, payload: payload)

      expect(event.structured_stack_trace).to be_present
      expect(event.structured_stack_trace.length).to eq(1)
      expect(event.culprit_frame).to be_present
      expect(event.has_structured_stack_trace?).to be true
    end

    it 'handles payload without structured_stack_trace' do
      payload = {
        exception_class: 'RuntimeError',
        message: 'simple error',
        backtrace: ["app/models/user.rb:10:in `save'"],
        occurred_at: Time.current.iso8601
      }

      event = Event.ingest_error(project: project, payload: payload)

      expect(event.structured_stack_trace).to eq([])
      expect(event.culprit_frame).to be_nil
      expect(event.has_structured_stack_trace?).to be false
    end
  end

  describe '#top_frame and #formatted_backtrace' do
    it 'extracts top frame and formats backtrace' do
      event = build(:event)
      expect(event.top_frame).to be_present
      expect(event.formatted_backtrace).to be_an(Array)
    end
  end

  describe '#structured_stack_trace' do
    it 'returns empty array when not present' do
      event = build(:event, context: {})
      expect(event.structured_stack_trace).to eq([])
    end

    it 'returns structured data when present (string keys)' do
      event = build(:event, context: {
        "structured_stack_trace" => [{ "file" => "test.rb", "line" => 1 }]
      })
      expect(event.structured_stack_trace).to eq([{ "file" => "test.rb", "line" => 1 }])
    end

    it 'returns structured data when present (symbol keys)' do
      event = build(:event, context: {
        structured_stack_trace: [{ file: "test.rb", line: 1 }]
      })
      expect(event.structured_stack_trace).to eq([{ file: "test.rb", line: 1 }])
    end
  end

  describe '#culprit_frame' do
    it 'returns nil when not present' do
      event = build(:event, context: {})
      expect(event.culprit_frame).to be_nil
    end

    it 'returns culprit frame when present' do
      culprit = { "file" => "app/models/user.rb", "line" => 42 }
      event = build(:event, context: { "culprit_frame" => culprit })
      expect(event.culprit_frame).to eq(culprit)
    end
  end

  describe '#has_structured_stack_trace?' do
    it 'returns false when empty' do
      event = build(:event, context: { "structured_stack_trace" => [] })
      expect(event.has_structured_stack_trace?).to be false
    end

    it 'returns true when present' do
      event = build(:event, context: {
        "structured_stack_trace" => [{ "file" => "test.rb" }]
      })
      expect(event.has_structured_stack_trace?).to be true
    end
  end
end
