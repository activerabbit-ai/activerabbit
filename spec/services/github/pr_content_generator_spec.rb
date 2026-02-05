require 'rails_helper'

RSpec.describe Github::PrContentGenerator, type: :service do
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }
  let(:issue) do
    create(:issue,
      project: project,
      account: account,
      exception_class: "NoMethodError",
      sample_message: "undefined method `foo' for nil:NilClass",
      controller_action: "UsersController#show",
      ai_summary: ai_summary
    )
  end
  let(:event) do
    create(:event,
      project: project,
      account: account,
      issue: issue,
      backtrace: ["/app/controllers/users_controller.rb:25:in `show'"]
    )
  end

  let(:ai_summary) do
    <<~SUMMARY
      ## Root Cause

      The error occurs because @user is nil when calling .foo method.

      ## Suggested Fix

      **Before:**

      ```ruby
      @user.foo
      ```

      **After:**

      ```ruby
      @user&.foo
      ```

      ## Prevention

      Always use safe navigation operator.
    SUMMARY
  end

  let(:service) { described_class.new(anthropic_key: "test-key") }

  before do
    ActsAsTenant.current_tenant = account
    issue.events << event
  end

  describe '#initialize' do
    it 'accepts anthropic_key' do
      service = described_class.new(anthropic_key: "test-key")
      expect(service).to be_a(Github::PrContentGenerator)
    end

    it 'uses ENV key when not provided' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return("env-key")

      service = described_class.new
      expect(service).to be_a(Github::PrContentGenerator)
    end
  end

  describe '#generate' do
    context 'when issue has AI summary' do
      it 'returns parsed PR content' do
        result = service.generate(issue)

        expect(result[:title]).to be_present
        expect(result[:body]).to be_present
        expect(result[:code_fix]).to be_present
        expect(result[:before_code]).to be_present
      end

      it 'extracts fix code from summary' do
        result = service.generate(issue)

        expect(result[:code_fix]).to include("@user&.foo")
      end

      it 'extracts before code from summary' do
        result = service.generate(issue)

        expect(result[:before_code]).to include("@user.foo")
      end

      it 'generates PR title from root cause' do
        result = service.generate(issue)

        expect(result[:title]).to start_with("fix:")
      end

      it 'includes issue details in body' do
        result = service.generate(issue)

        expect(result[:body]).to include("NoMethodError")
        expect(result[:body]).to include("UsersController#show")
      end
    end

    context 'when issue has no AI summary but has API key' do
      let(:ai_summary) { nil }

      let(:api_response) do
        {
          "content" => [
            {
              "type" => "text",
              "text" => "TITLE: fix: handle nil user\nROOT_CAUSE: User is nil\nFIX: Use safe navigation\nPREVENTION: Add validation"
            }
          ]
        }
      end

      before do
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .to_return(status: 200, body: api_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'generates content via AI' do
        result = service.generate(issue)

        expect(result[:title]).to include("fix:")
        expect(result[:body]).to be_present
      end

      it 'uses claude-opus-4 model' do
        service.generate(issue)

        expect(WebMock).to have_requested(:post, "https://api.anthropic.com/v1/messages")
          .with(body: hash_including("model" => "claude-opus-4-20250514"))
      end
    end

    context 'when issue has no AI summary and no API key' do
      let(:ai_summary) { nil }
      let(:service) { described_class.new(anthropic_key: nil) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("ANTHROPIC_API_KEY").and_return(nil)
      end

      it 'returns basic fallback content' do
        result = service.generate(issue)

        expect(result[:title]).to include("NoMethodError")
        expect(result[:body]).to include("Bug Fix")
        expect(result[:code_fix]).to be_nil
      end
    end
  end

  describe '#parse_ai_summary' do
    it 'extracts root cause section' do
      result = service.send(:parse_ai_summary, ai_summary)

      expect(result[:root_cause]).to include("@user is nil")
    end

    it 'extracts fix section' do
      result = service.send(:parse_ai_summary, ai_summary)

      expect(result[:fix]).to be_present
    end

    it 'extracts fix code (after block)' do
      result = service.send(:parse_ai_summary, ai_summary)

      expect(result[:fix_code]).to include("@user&.foo")
    end

    it 'extracts before code' do
      result = service.send(:parse_ai_summary, ai_summary)

      expect(result[:before_code]).to include("@user.foo")
    end

    it 'extracts prevention section' do
      result = service.send(:parse_ai_summary, ai_summary)

      expect(result[:prevention]).to include("safe navigation")
    end

    it 'handles empty summary' do
      result = service.send(:parse_ai_summary, "")

      expect(result[:root_cause]).to be_nil
      expect(result[:fix]).to be_nil
      expect(result[:fix_code]).to be_nil
    end
  end

  describe '#extract_method_from_code' do
    it 'extracts method from class wrapper' do
      code = <<~RUBY
        class UsersController < ApplicationController
          def show
            @user = User.find(params[:id])
          end
        end
      RUBY

      result = service.send(:extract_method_from_code, code)

      expect(result).to include("def show")
      expect(result).to include("@user = User.find")
      expect(result).not_to include("class UsersController")
    end

    it 'returns code as-is when no class wrapper' do
      code = <<~RUBY
        def show
          @user = User.find(params[:id])
        end
      RUBY

      result = service.send(:extract_method_from_code, code)

      expect(result).to eq(code)
    end
  end

  describe '#validate_method_structure' do
    it 'returns true for valid method' do
      code = "def show\n  @user = User.find(params[:id])\nend"

      expect(service.send(:validate_method_structure, code)).to be true
    end

    it 'returns falsy for incomplete method' do
      code = "def show\n  @user = User.find(params[:id])"

      expect(service.send(:validate_method_structure, code)).to be_falsy
    end

    it 'returns false for blank code' do
      expect(service.send(:validate_method_structure, "")).to be false
    end
  end

  describe '#parse_multi_file_fixes' do
    it 'parses first file only due to MAX_FILES_PER_FIX limit' do
      # With MAX_FILES_PER_FIX = 1, only the first file should be parsed
      multi_file_fix = <<~SUMMARY
        ### File 1: `app/controllers/users_controller.rb`
        **Line:** 25

        **Before:**

        ```ruby
        @user = User.find(params[:id])
        ```

        **After:**

        ```ruby
        @user = User.find_by(id: params[:id])
        ```

        ### File 2: `app/models/user.rb`
        **Line:** 10

        **Before:**

        ```ruby
        validates :email, presence: true
        ```

        **After:**

        ```ruby
        validates :email, presence: true, uniqueness: true
        ```
      SUMMARY

      result = service.send(:parse_multi_file_fixes, multi_file_fix)

      # Limited to 1 file (MAX_FILES_PER_FIX)
      expect(result.size).to eq(1)
      expect(result[0][:file_path]).to eq("app/controllers/users_controller.rb")
      expect(result[0][:before_code]).to include("User.find(params[:id])")
      expect(result[0][:after_code]).to include("User.find_by(id: params[:id])")
    end

    it 'handles single file in multi-file format' do
      single_file_fix = <<~SUMMARY
        ### File 1: `app/services/foo_service.rb`
        **Line:** 5

        **Before:**

        ```ruby
        old_code
        ```

        **After:**

        ```ruby
        new_code
        ```
      SUMMARY

      result = service.send(:parse_multi_file_fixes, single_file_fix)

      expect(result.size).to eq(1)
      expect(result[0][:file_path]).to eq("app/services/foo_service.rb")
    end
  end

  describe '#parse_ai_summary with multi-file fixes' do
    it 'limits file_fixes to MAX_FILES_PER_FIX and captures related changes' do
      multi_file_summary = <<~SUMMARY
        ## Root Cause

        Multiple issues across files.

        ## Suggested Fix

        ### File 1: `app/controllers/api_controller.rb`
        **Line:** 10

        **Before:**

        ```ruby
        render json: data
        ```

        **After:**

        ```ruby
        render json: data, status: :ok
        ```

        ### File 2: `app/models/data.rb`
        **Line:** 5

        **Before:**

        ```ruby
        def process; end
        ```

        **After:**

        ```ruby
        def process
          validate!
        end
        ```

        ## Related Changes

        - `app/models/data.rb`: Update process method

        ## Prevention

        Test your code.
      SUMMARY

      result = service.send(:parse_ai_summary, multi_file_summary)

      expect(result[:file_fixes]).to be_present
      # Limited to 1 file (MAX_FILES_PER_FIX)
      expect(result[:file_fixes].size).to eq(1)
      expect(result[:root_cause]).to include("Multiple issues")
      expect(result[:prevention]).to include("Test your code")
      # Backward compatibility - first file's fix becomes the primary fix
      expect(result[:fix_code]).to include("status: :ok")
      # Related changes captured
      expect(result[:related_changes]).to include("app/models/data.rb")
    end

    it 'enforces MAX_FILES_PER_FIX safety limit (1 file only)' do
      # Create a summary with 3 files (exceeds limit of 1)
      many_files_summary = <<~SUMMARY
        ## Root Cause

        Issues across many files.

        ## Suggested Fix

        ### File 1: `app/file1.rb`
        **Before:**
        ```ruby
        code1
        ```
        **After:**
        ```ruby
        fixed1
        ```

        ### File 2: `app/file2.rb`
        **Before:**
        ```ruby
        code2
        ```
        **After:**
        ```ruby
        fixed2
        ```

        ### File 3: `app/file3.rb`
        **Before:**
        ```ruby
        code3
        ```
        **After:**
        ```ruby
        fixed3
        ```

        ## Related Changes

        - `app/file2.rb`: Add validation method
        - `app/file3.rb`: Update association

        ## Prevention

        Review all changes.
      SUMMARY

      result = service.send(:parse_ai_summary, many_files_summary)

      # Should be limited to MAX_FILES_PER_FIX (1)
      expect(result[:file_fixes].size).to eq(AiSummaryService::MAX_FILES_PER_FIX)
      expect(result[:file_fixes].size).to eq(1)
      
      # Should have first file only
      expect(result[:file_fixes].map { |f| f[:file_path] }).to eq([
        "app/file1.rb"
      ])
      
      # Related changes should be captured for display
      expect(result[:related_changes]).to include("app/file2.rb")
      expect(result[:related_changes]).to include("app/file3.rb")
    end
  end
end
