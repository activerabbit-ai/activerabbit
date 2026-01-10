require 'rails_helper'

RSpec.describe ErrorsHelper, type: :helper do
  describe "#parse_backtrace_frame" do
    it "parses standard Ruby backtrace format" do
      frame = helper.parse_backtrace_frame("app/controllers/users_controller.rb:25:in `show'")

      expect(frame[:file]).to eq("app/controllers/users_controller.rb")
      expect(frame[:line]).to eq(25)
      expect(frame[:method]).to eq("show")
      expect(frame[:in_app]).to be true
      expect(frame[:frame_type]).to eq(:controller)
    end

    it "parses gem/library backtrace format" do
      # Note: paths with lib/ match :library before :gem in classify_frame
      frame = helper.parse_backtrace_frame("/gems/rails-7.0/lib/action_controller.rb:100:in `process'")

      expect(frame[:file]).to eq("/gems/rails-7.0/lib/action_controller.rb")
      expect(frame[:line]).to eq(100)
      expect(frame[:in_app]).to be false
      expect(frame[:frame_type]).to eq(:library)
    end

    it "handles hash input (from client structured_stack_trace)" do
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

      frame = helper.parse_backtrace_frame(client_frame)

      expect(frame[:file]).to eq("app/models/user.rb")
      expect(frame[:line]).to eq(42)
      expect(frame[:method]).to eq("validate_email")
      expect(frame[:in_app]).to be true
      expect(frame[:frame_type]).to eq(:model)
      expect(frame[:source_context]).to be_present
      expect(frame[:source_context][:file_exists]).to be true
    end

    it "returns nil for blank input" do
      expect(helper.parse_backtrace_frame(nil)).to be_nil
      expect(helper.parse_backtrace_frame("")).to be_nil
    end

    it "handles malformed backtrace gracefully" do
      frame = helper.parse_backtrace_frame("some random text without colon format")

      expect(frame[:raw]).to eq("some random text without colon format")
      expect(frame[:file]).to be_nil
      expect(frame[:in_app]).to be false
      expect(frame[:frame_type]).to eq(:unknown)
    end
  end

  describe "#normalize_client_frame" do
    it "handles string keys" do
      frame = helper.normalize_client_frame({
        "file" => "app/services/payment.rb",
        "line" => 10,
        "method" => "charge"
      })

      expect(frame[:file]).to eq("app/services/payment.rb")
      expect(frame[:line]).to eq(10)
    end

    it "handles symbol keys" do
      frame = helper.normalize_client_frame({
        file: "app/services/payment.rb",
        line: 10,
        method: "charge"
      })

      expect(frame[:file]).to eq("app/services/payment.rb")
      expect(frame[:line]).to eq(10)
    end
  end

  describe "#normalize_source_context" do
    it "normalizes source context from client" do
      ctx = helper.normalize_source_context({
        "lines_before" => ["line 1", "line 2"],
        "line_content" => "error line",
        "lines_after" => ["line 4"],
        "start_line" => 1
      })

      expect(ctx[:lines_before].length).to eq(2)
      expect(ctx[:lines_before][0]).to eq({ number: 1, content: "line 1" })
      expect(ctx[:lines_before][1]).to eq({ number: 2, content: "line 2" })
      expect(ctx[:line_content]).to eq({ number: 3, content: "error line" })
      expect(ctx[:lines_after][0]).to eq({ number: 4, content: "line 4" })
      expect(ctx[:file_exists]).to be true
    end

    it "returns nil for blank context" do
      expect(helper.normalize_source_context(nil)).to be_nil
      expect(helper.normalize_source_context({})).to be_nil
    end
  end

  describe "#parse_backtrace" do
    let(:backtrace_lines) do
      [
        "app/controllers/users_controller.rb:25:in `show'",
        "/gems/rails/lib/action.rb:10:in `call'"
      ]
    end

    let(:event) do
      build(:event, backtrace: backtrace_lines)
    end

    it "parses backtrace from event" do
      # Ensure the event has the backtrace we expect
      allow(event).to receive(:formatted_backtrace).and_return(backtrace_lines)
      allow(event).to receive(:structured_stack_trace).and_return([])

      frames = helper.parse_backtrace(event)

      expect(frames.length).to eq(2)
      expect(frames[0][:file]).to eq("app/controllers/users_controller.rb")
      expect(frames[1][:file]).to eq("/gems/rails/lib/action.rb")
    end

    it "uses structured_stack_trace when available" do
      allow(event).to receive(:structured_stack_trace).and_return([
        { "file" => "app/models/user.rb", "line" => 5, "method" => "save", "in_app" => true }
      ])

      frames = helper.parse_backtrace(event)

      expect(frames.length).to eq(1)
      expect(frames[0][:file]).to eq("app/models/user.rb")
    end

    it "handles array input directly" do
      frames = helper.parse_backtrace([
        "app/models/user.rb:10:in `validate'"
      ])

      expect(frames.length).to eq(1)
      expect(frames[0][:file]).to eq("app/models/user.rb")
    end

    it "handles empty backtrace" do
      expect(helper.parse_backtrace([])).to eq([])
      expect(helper.parse_backtrace(nil)).to eq([])
    end
  end

  describe "#in_app_frame?" do
    it "identifies app frames" do
      expect(helper.in_app_frame?("app/controllers/test.rb")).to be true
      expect(helper.in_app_frame?("app/models/user.rb")).to be true
      expect(helper.in_app_frame?("lib/validator.rb")).to be true
    end

    it "identifies non-app frames" do
      expect(helper.in_app_frame?("/gems/rails/lib/test.rb")).to be false
      expect(helper.in_app_frame?("/ruby/3.0.0/lib/net/http.rb")).to be false
    end

    it "handles blank input" do
      expect(helper.in_app_frame?(nil)).to be false
      expect(helper.in_app_frame?("")).to be false
    end
  end

  describe "#classify_frame" do
    # Note: classify_frame uses order-dependent matching:
    # controllers matches before concerns, lib/ matches before gems
    {
      "app/controllers/users_controller.rb" => :controller,
      "app/models/user.rb" => :model,
      "app/services/payment.rb" => :service,
      "app/jobs/sync_job.rb" => :job,
      "app/views/users/show.html.erb" => :view,
      "app/helpers/application_helper.rb" => :helper,
      "app/mailers/user_mailer.rb" => :mailer,
      # controllers/ matches before concerns/ in the case statement
      "app/controllers/concerns/auth.rb" => :controller,
      # Pure concerns path matches :concern
      "app/concerns/auth.rb" => :concern,
      "lib/validator.rb" => :library,
      # lib/ matches before gems/ in the case statement
      "/gems/rails/lib/test.rb" => :library,
      # Path without lib/ matches :gem
      "/path/to/gems/rails-7.0/action.rb" => :gem
    }.each do |file, expected_type|
      it "classifies #{file} as #{expected_type}" do
        expect(helper.classify_frame(file)).to eq(expected_type)
      end
    end
  end

  describe "#frame_type_badge_class" do
    it "returns correct CSS classes for each type" do
      expect(helper.frame_type_badge_class(:controller)).to include("blue")
      expect(helper.frame_type_badge_class(:model)).to include("green")
      expect(helper.frame_type_badge_class(:service)).to include("purple")
      expect(helper.frame_type_badge_class(:gem)).to include("gray")
    end
  end

  describe "#frame_type_label" do
    it "returns human-readable labels" do
      expect(helper.frame_type_label(:controller)).to eq("Controller")
      expect(helper.frame_type_label(:model)).to eq("Model")
      expect(helper.frame_type_label(:service)).to eq("Service")
      expect(helper.frame_type_label(:gem)).to eq("Gem")
    end

    it "returns nil for unknown types" do
      expect(helper.frame_type_label(:other)).to be_nil
      expect(helper.frame_type_label(:unknown)).to be_nil
    end
  end

  describe "#truncate_file_path" do
    it "truncates long paths" do
      long_path = "app/controllers/admin/users/settings/preferences_controller.rb"
      result = helper.truncate_file_path(long_path, max_parts: 3)

      expect(result).to start_with("...")
      expect(result.split("/").length).to be <= 4 # ... + 3 parts
    end

    it "preserves short paths" do
      short_path = "app/models/user.rb"
      expect(helper.truncate_file_path(short_path)).to eq(short_path)
    end
  end

  describe "#clean_method_name" do
    it "cleans block notation" do
      expect(helper.clean_method_name("block in process")).to eq("process")
      expect(helper.clean_method_name("block (2 levels) in execute")).to eq("execute")
    end

    it "cleans rescue/ensure notation" do
      expect(helper.clean_method_name("rescue in save")).to eq("save")
      expect(helper.clean_method_name("ensure in cleanup")).to eq("cleanup")
    end

    it "cleans class/module notation" do
      # When the result would be empty, the original is returned due to .presence fallback
      # This is intentional to avoid showing blank method names
      expect(helper.clean_method_name("<class:User>")).to eq("<class:User>")
      expect(helper.clean_method_name("<module:Admin>")).to eq("<module:Admin>")
      # When combined with other content, the brackets are removed
      expect(helper.clean_method_name("<class:User> initialize")).to eq("initialize")
    end

    it "returns 'unknown' for blank input" do
      expect(helper.clean_method_name(nil)).to eq("unknown")
      expect(helper.clean_method_name("")).to eq("unknown")
    end
  end

  describe "#find_culprit_frame" do
    it "finds first in-app frame" do
      frames = [
        { in_app: false, file: "/gems/test.rb" },
        { in_app: true, file: "app/models/user.rb" },
        { in_app: true, file: "app/controllers/users.rb" }
      ]

      culprit = helper.find_culprit_frame(frames)
      expect(culprit[:file]).to eq("app/models/user.rb")
    end

    it "returns nil if no in-app frames" do
      frames = [
        { in_app: false, file: "/gems/test.rb" }
      ]

      expect(helper.find_culprit_frame(frames)).to be_nil
    end
  end
end

