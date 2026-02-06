require "test_helper"

class ErrorsHelperTest < ActionView::TestCase
  # parse_backtrace_frame tests

  test "parses standard Ruby backtrace format" do
    frame = parse_backtrace_frame("app/controllers/users_controller.rb:25:in `show'")

    assert_equal "app/controllers/users_controller.rb", frame[:file]
    assert_equal 25, frame[:line]
    assert_equal "show", frame[:method]
    assert frame[:in_app]
    assert_equal :controller, frame[:frame_type]
  end

  test "parses gem/library backtrace format" do
    frame = parse_backtrace_frame("/gems/rails-7.0/lib/action_controller.rb:100:in `process'")

    assert_equal "/gems/rails-7.0/lib/action_controller.rb", frame[:file]
    assert_equal 100, frame[:line]
    refute frame[:in_app]
    assert_equal :library, frame[:frame_type]
  end

  test "handles hash input from client structured_stack_trace" do
    client_frame = {
      "file" => "app/models/user.rb",
      "line" => 42,
      "method" => "validate_email",
      "in_app" => true,
      "frame_type" => "model",
      "source_context" => {
        "lines_before" => ["  def validate_email", "    return if email.blank?"],
        "line_content" => "    raise 'Invalid email'",
        "lines_after" => ["  end"],
        "start_line" => 40
      }
    }

    frame = parse_backtrace_frame(client_frame)

    assert_equal "app/models/user.rb", frame[:file]
    assert_equal 42, frame[:line]
    assert_equal "validate_email", frame[:method]
    assert frame[:in_app]
    assert_equal :model, frame[:frame_type]
    assert frame[:source_context].present?
    assert frame[:source_context][:file_exists]
  end

  test "returns nil for blank input" do
    assert_nil parse_backtrace_frame(nil)
    assert_nil parse_backtrace_frame("")
  end

  test "handles malformed backtrace gracefully" do
    frame = parse_backtrace_frame("some random text without colon format")

    assert_equal "some random text without colon format", frame[:raw]
    assert_nil frame[:file]
    refute frame[:in_app]
    assert_equal :unknown, frame[:frame_type]
  end

  # normalize_client_frame tests

  test "normalize_client_frame handles string keys" do
    frame = normalize_client_frame({
      "file" => "app/services/payment.rb",
      "line" => 10,
      "method" => "charge"
    })

    assert_equal "app/services/payment.rb", frame[:file]
    assert_equal 10, frame[:line]
  end

  test "normalize_client_frame handles symbol keys" do
    frame = normalize_client_frame({
      file: "app/services/payment.rb",
      line: 10,
      method: "charge"
    })

    assert_equal "app/services/payment.rb", frame[:file]
    assert_equal 10, frame[:line]
  end

  # normalize_source_context tests

  test "normalizes source context from client" do
    ctx = normalize_source_context({
      "lines_before" => ["line 1", "line 2"],
      "line_content" => "error line",
      "lines_after" => ["line 4"],
      "start_line" => 1
    })

    assert_equal 2, ctx[:lines_before].length
    assert_equal({ number: 1, content: "line 1" }, ctx[:lines_before][0])
    assert_equal({ number: 2, content: "line 2" }, ctx[:lines_before][1])
    assert_equal({ number: 3, content: "error line" }, ctx[:line_content])
    assert_equal({ number: 4, content: "line 4" }, ctx[:lines_after][0])
    assert ctx[:file_exists]
  end

  test "normalize_source_context returns nil for blank context" do
    assert_nil normalize_source_context(nil)
    assert_nil normalize_source_context({})
  end

  # parse_backtrace tests

  test "parses backtrace from array input" do
    frames = parse_backtrace([
      "app/models/user.rb:10:in `validate'"
    ])

    assert_equal 1, frames.length
    assert_equal "app/models/user.rb", frames[0][:file]
  end

  test "handles empty backtrace" do
    assert_equal [], parse_backtrace([])
    assert_equal [], parse_backtrace(nil)
  end

  # in_app_frame? tests

  test "identifies app frames" do
    assert in_app_frame?("app/controllers/test.rb")
    assert in_app_frame?("app/models/user.rb")
    assert in_app_frame?("lib/validator.rb")
  end

  test "identifies non-app frames" do
    refute in_app_frame?("/gems/rails/lib/test.rb")
    refute in_app_frame?("/ruby/3.0.0/lib/net/http.rb")
  end

  test "in_app_frame handles blank input" do
    refute in_app_frame?(nil)
    refute in_app_frame?("")
  end

  # classify_frame tests

  test "classifies controller frame" do
    assert_equal :controller, classify_frame("app/controllers/users_controller.rb")
  end

  test "classifies model frame" do
    assert_equal :model, classify_frame("app/models/user.rb")
  end

  test "classifies service frame" do
    assert_equal :service, classify_frame("app/services/payment.rb")
  end

  test "classifies job frame" do
    assert_equal :job, classify_frame("app/jobs/sync_job.rb")
  end

  test "classifies view frame" do
    assert_equal :view, classify_frame("app/views/users/show.html.erb")
  end

  test "classifies helper frame" do
    assert_equal :helper, classify_frame("app/helpers/application_helper.rb")
  end

  test "classifies mailer frame" do
    assert_equal :mailer, classify_frame("app/mailers/user_mailer.rb")
  end

  test "classifies controller concern frame as controller" do
    assert_equal :controller, classify_frame("app/controllers/concerns/auth.rb")
  end

  test "classifies pure concern frame" do
    assert_equal :concern, classify_frame("app/concerns/auth.rb")
  end

  test "classifies library frame" do
    assert_equal :library, classify_frame("lib/validator.rb")
  end

  test "classifies gem with lib path as library" do
    assert_equal :library, classify_frame("/gems/rails/lib/test.rb")
  end

  test "classifies gem without lib path" do
    assert_equal :gem, classify_frame("/path/to/gems/rails-7.0/action.rb")
  end

  # frame_type_badge_class tests

  test "returns correct CSS classes for frame types" do
    assert_includes frame_type_badge_class(:controller), "blue"
    assert_includes frame_type_badge_class(:model), "green"
    assert_includes frame_type_badge_class(:service), "purple"
    assert_includes frame_type_badge_class(:gem), "gray"
  end

  # frame_type_label tests

  test "returns human-readable labels" do
    assert_equal "Controller", frame_type_label(:controller)
    assert_equal "Model", frame_type_label(:model)
    assert_equal "Service", frame_type_label(:service)
    assert_equal "Gem", frame_type_label(:gem)
  end

  test "returns nil for unknown types" do
    assert_nil frame_type_label(:other)
    assert_nil frame_type_label(:unknown)
  end

  # truncate_file_path tests

  test "truncates long paths" do
    long_path = "app/controllers/admin/users/settings/preferences_controller.rb"
    result = truncate_file_path(long_path, max_parts: 3)

    assert result.start_with?("...")
    assert result.split("/").length <= 4 # ... + 3 parts
  end

  test "preserves short paths" do
    short_path = "app/models/user.rb"
    assert_equal short_path, truncate_file_path(short_path)
  end

  # clean_method_name tests

  test "cleans block notation" do
    assert_equal "process", clean_method_name("block in process")
    assert_equal "execute", clean_method_name("block (2 levels) in execute")
  end

  test "cleans rescue/ensure notation" do
    assert_equal "save", clean_method_name("rescue in save")
    assert_equal "cleanup", clean_method_name("ensure in cleanup")
  end

  test "cleans class/module notation" do
    # When the result would be empty, the original is returned due to .presence fallback
    assert_equal "<class:User>", clean_method_name("<class:User>")
    assert_equal "<module:Admin>", clean_method_name("<module:Admin>")
    # When combined with other content, the brackets are removed
    assert_equal "initialize", clean_method_name("<class:User> initialize")
  end

  test "returns unknown for blank method name" do
    assert_equal "unknown", clean_method_name(nil)
    assert_equal "unknown", clean_method_name("")
  end

  # find_culprit_frame tests

  test "finds first in-app frame" do
    frames = [
      { in_app: false, file: "/gems/test.rb" },
      { in_app: true, file: "app/models/user.rb" },
      { in_app: true, file: "app/controllers/users.rb" }
    ]

    culprit = find_culprit_frame(frames)
    assert_equal "app/models/user.rb", culprit[:file]
  end

  test "returns nil if no in-app frames" do
    frames = [
      { in_app: false, file: "/gems/test.rb" }
    ]

    assert_nil find_culprit_frame(frames)
  end
end
