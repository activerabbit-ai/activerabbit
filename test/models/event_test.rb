require "test_helper"

class EventTest < ActiveSupport::TestCase
  # ingest_error

  test "ingest_error creates an issue and an event" do
    project = projects(:default)
    payload = {
      exception_class: "ArgumentError",
      message: "bad arg",
      backtrace: ["/app/controllers/example_controller.rb:5:in `show'"],
      request_path: "/example",
      request_method: "GET",
      environment: "production",
      occurred_at: Time.current.iso8601
    }

    assert_difference ["Issue.count", "Event.count"], 1 do
      Event.ingest_error(project: project, payload: payload)
    end
  end

  test "ingest_error stores structured_stack_trace in context" do
    project = projects(:default)
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
      exception_class: "ArgumentError",
      message: "test error",
      backtrace: ["app/controllers/users_controller.rb:25:in `show'"],
      structured_stack_trace: structured_frames,
      culprit_frame: structured_frames.first,
      occurred_at: Time.current.iso8601
    }

    event = Event.ingest_error(project: project, payload: payload)

    assert event.structured_stack_trace.present?
    assert_equal 1, event.structured_stack_trace.length
    assert event.culprit_frame.present?
    assert event.has_structured_stack_trace?
  end

  test "ingest_error handles payload without structured_stack_trace" do
    project = projects(:default)
    payload = {
      exception_class: "RuntimeError",
      message: "simple error",
      backtrace: ["app/models/user.rb:10:in `save'"],
      occurred_at: Time.current.iso8601
    }

    event = Event.ingest_error(project: project, payload: payload)

    assert_equal [], event.structured_stack_trace
    assert_nil event.culprit_frame
    refute event.has_structured_stack_trace?
  end

  # top_frame and formatted_backtrace

  test "top_frame returns first frame" do
    event = events(:default)
    assert event.top_frame.present?
  end

  test "formatted_backtrace returns an array" do
    event = events(:default)
    assert event.formatted_backtrace.is_a?(Array)
  end

  # structured_stack_trace

  test "structured_stack_trace returns empty array when not present" do
    event = events(:default)
    event.context = {}
    assert_equal [], event.structured_stack_trace
  end

  test "structured_stack_trace returns data when present with string keys" do
    event = events(:default)
    event.context = { "structured_stack_trace" => [{ "file" => "test.rb", "line" => 1 }] }
    assert_equal [{ "file" => "test.rb", "line" => 1 }], event.structured_stack_trace
  end

  test "structured_stack_trace returns data when present with symbol keys" do
    event = events(:default)
    event.context = { structured_stack_trace: [{ file: "test.rb", line: 1 }] }
    # Rails JSON serialization converts symbol keys to strings
    assert_equal [{ "file" => "test.rb", "line" => 1 }], event.structured_stack_trace
  end

  # culprit_frame

  test "culprit_frame returns nil when not present" do
    event = events(:default)
    event.context = {}
    assert_nil event.culprit_frame
  end

  test "culprit_frame returns data when present" do
    event = events(:default)
    culprit = { "file" => "app/models/user.rb", "line" => 42 }
    event.context = { "culprit_frame" => culprit }
    assert_equal culprit, event.culprit_frame
  end

  # has_structured_stack_trace?

  test "has_structured_stack_trace returns false when empty" do
    event = events(:default)
    event.context = { "structured_stack_trace" => [] }
    refute event.has_structured_stack_trace?
  end

  test "has_structured_stack_trace returns true when present" do
    event = events(:default)
    event.context = { "structured_stack_trace" => [{ "file" => "test.rb" }] }
    assert event.has_structured_stack_trace?
  end
end
