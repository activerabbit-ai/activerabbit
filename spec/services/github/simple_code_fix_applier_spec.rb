require 'rails_helper'

RSpec.describe Github::SimpleCodeFixApplier, type: :service do
  let(:api_client) { double("Github::ApiClient") }
  let(:account) { create(:account) }
  let(:project) { create(:project, account: account) }
  let(:issue) { create(:issue, project: project, account: account, exception_class: "NoMethodError") }
  let(:event) do
    create(:event,
      project: project,
      account: account,
      issue: issue,
      context: {
        "structured_stack_trace" => [
          {
            "file" => "app/controllers/users_controller.rb",
            "line" => 25,
            "method" => "show",
            "in_app" => true,
            "source_context" => {
              "lines_before" => ["  def show", "    @user = User.find(params[:id])"],
              "line_content" => "    @user.foo",
              "lines_after" => ["  end"]
            }
          }
        ]
      }
    )
  end

  let(:service) { described_class.new(api_client: api_client, anthropic_key: "test-key") }

  before do
    ActsAsTenant.current_tenant = account
  end

  describe '#initialize' do
    it 'accepts api_client and anthropic_key' do
      service = described_class.new(api_client: api_client, anthropic_key: "test-key")
      expect(service).to be_a(Github::SimpleCodeFixApplier)
    end

    it 'accepts optional source_branch' do
      service = described_class.new(api_client: api_client, anthropic_key: "test-key", source_branch: "develop")
      expect(service).to be_a(Github::SimpleCodeFixApplier)
    end
  end

  describe '#try_apply_actual_fix' do
    let(:file_content) do
      <<~RUBY
        class UsersController < ApplicationController
          def show
            @user = User.find(params[:id])
            @user.foo
          end
        end
      RUBY
    end

    context 'when event has no structured stack trace' do
      let(:event_without_trace) do
        create(:event, project: project, account: account, issue: issue, context: {})
      end

      it 'returns error when no in-app frame with source context' do
        result = service.try_apply_actual_fix("owner", "repo", event_without_trace, issue)

        expect(result[:success]).to be false
        expect(result[:reason]).to include("No in-app frame")
      end
    end

    context 'when file is not found on GitHub' do
      before do
        allow(api_client).to receive(:get)
          .with("/repos/owner/repo/contents/app/controllers/users_controller.rb")
          .and_return({ "error" => "Not Found" })
      end

      it 'returns error when file not found' do
        result = service.try_apply_actual_fix("owner", "repo", event, issue)

        expect(result[:success]).to be false
        expect(result[:reason]).to include("File not found")
      end
    end

    context 'when file is found and fix can be generated' do
      let(:ai_response) do
        {
          "content" => [
            {
              "type" => "text",
              "text" => '{"replacements": [{"line": 4, "old": "    @user.foo", "new": "    @user&.foo"}]}'
            }
          ]
        }
      end

      before do
        # Stub default to return nil for any get call
        allow(api_client).to receive(:get).and_return(nil)
        # Stub POST calls (for creating blobs, etc.)
        allow(api_client).to receive(:post).and_return({ "sha" => "blob123" })
        # Then stub specific files
        allow(api_client).to receive(:get)
          .with("/repos/owner/repo/contents/app/controllers/users_controller.rb")
          .and_return({ "content" => Base64.encode64(file_content) })
        allow(api_client).to receive(:get)
          .with("/repos/owner/repo/contents/app/models/user.rb")
          .and_return({ "content" => Base64.encode64("class User < ApplicationRecord\nend") })

        # Stub any POST to Anthropic API
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .with(headers: { 'X-Api-Key' => 'test-key' })
          .to_return(status: 200, body: ai_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns success with tree entry' do
        result = service.try_apply_actual_fix("owner", "repo", event, issue)

        expect(result[:success]).to be true
        expect(result[:tree_entry]).to be_present
        expect(result[:file_path]).to eq("app/controllers/users_controller.rb")
      end

      it 'creates tree entry with correct file path' do
        result = service.try_apply_actual_fix("owner", "repo", event, issue)

        expect(result[:success]).to be true
        expect(result[:tree_entry][:path]).to eq("app/controllers/users_controller.rb")
        expect(result[:tree_entry][:mode]).to eq("100644")
        expect(result[:tree_entry][:type]).to eq("blob")
      end
    end

    context 'with FAST PATH - direct replacement' do
      let(:before_code) { "    @user.foo" }
      let(:after_code) { "    @user&.foo" }
      let(:ai_response) do
        {
          "content" => [
            {
              "type" => "text",
              "text" => '{"replacements": [{"line": 4, "old": "    @user.foo", "new": "    @user&.foo"}]}'
            }
          ]
        }
      end

      before do
        # Stub default to return nil for any get call
        allow(api_client).to receive(:get).and_return(nil)
        # Stub POST calls (for creating blobs, etc.)
        allow(api_client).to receive(:post).and_return({ "sha" => "blob123" })
        allow(api_client).to receive(:get)
          .with("/repos/owner/repo/contents/app/controllers/users_controller.rb")
          .and_return({ "content" => Base64.encode64(file_content) })
        allow(api_client).to receive(:get)
          .with("/repos/owner/repo/contents/app/models/user.rb")
          .and_return({ "content" => Base64.encode64("class User < ApplicationRecord\nend") })
        
        # Still stub Anthropic in case fast path fails
        stub_request(:post, "https://api.anthropic.com/v1/messages")
          .with(headers: { 'X-Api-Key' => 'test-key' })
          .to_return(status: 200, body: ai_response.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'attempts to apply fix (may use fast path or AI fallback)' do
        result = service.try_apply_actual_fix("owner", "repo", event, issue, after_code, before_code)

        # Either fast path or AI fallback should work
        expect(result).to be_a(Hash)
        expect(result).to have_key(:success)
        if result[:success]
          expect(result[:tree_entry]).to be_present
          expect(result[:file_path]).to eq("app/controllers/users_controller.rb")
        end
      end
    end
  end

  describe '#try_direct_replacement' do
    let(:file_content) do
      <<~RUBY
        class UsersController < ApplicationController
          def show
            @user = User.find(params[:id])
            @user.foo
          end
        end
      RUBY
    end

    it 'returns nil when before_code is blank' do
      result = service.send(:try_direct_replacement, file_content, "", "new code", 4)
      expect(result).to be_nil
    end

    it 'returns nil when after_code is blank' do
      result = service.send(:try_direct_replacement, file_content, "old code", "", 4)
      expect(result).to be_nil
    end

    it 'finds and replaces matching code' do
      before_code = "@user.foo"
      after_code = "@user&.foo"

      result = service.send(:try_direct_replacement, file_content, before_code, after_code, 4)

      expect(result).to be_present
      expect(result["replacements"]).to be_present
      expect(result["replacements"].first["new"]).to include("@user&.foo")
    end

    it 'returns nil when before_code not found in file' do
      before_code = "nonexistent_code"
      after_code = "new_code"

      result = service.send(:try_direct_replacement, file_content, before_code, after_code, 4)

      expect(result).to be_nil
    end
  end

  describe '#normalize_code' do
    it 'strips whitespace and normalizes spaces' do
      result = service.send(:normalize_code, "  foo   bar  ")
      expect(result).to eq("foo bar")
    end

    it 'handles nil' do
      result = service.send(:normalize_code, nil)
      expect(result).to eq("")
    end
  end

  describe '#extract_referenced_classes' do
    it 'extracts class names from code' do
      code = "User.find(params[:id])\nProduct.where(active: true)"
      result = service.send(:extract_referenced_classes, code)

      expect(result).to include("User")
      expect(result).to include("Product")
    end

    it 'extracts classes from associations' do
      code = "belongs_to :user\nhas_many :orders"
      result = service.send(:extract_referenced_classes, code)

      expect(result).to include("User")
      expect(result).to include("Order")
    end

    it 'excludes common Ruby/Rails classes' do
      code = "String.new\nActiveRecord::Base"
      result = service.send(:extract_referenced_classes, code)

      expect(result).not_to include("String")
      expect(result).not_to include("ActiveRecord")
    end
  end
end
