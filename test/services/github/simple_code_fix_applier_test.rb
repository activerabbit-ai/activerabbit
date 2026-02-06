require "test_helper"

class Github::SimpleCodeFixApplierTest < ActiveSupport::TestCase
  setup do
    @api_client = Object.new
    @issue = issues(:open_issue)
    @event = events(:default)
    @event.update!(
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

  test "accepts api_client and anthropic_key on initialize" do
    service = Github::SimpleCodeFixApplier.new(api_client: @api_client, anthropic_key: "test-key")
    assert service.is_a?(Github::SimpleCodeFixApplier)
  end

  test "accepts optional source_branch" do
    service = Github::SimpleCodeFixApplier.new(api_client: @api_client, anthropic_key: "test-key", source_branch: "develop")
    assert service.is_a?(Github::SimpleCodeFixApplier)
  end

  # try_apply_actual_fix

  test "returns error when event has no structured stack trace" do
    @event.update!(context: {})
    service = Github::SimpleCodeFixApplier.new(api_client: @api_client, anthropic_key: "test-key")

    result = service.try_apply_actual_fix("owner", "repo", @event, @issue)

    refute result[:success]
    assert_includes result[:reason], "No in-app frame"
  end

  # try_direct_replacement

  test "try_direct_replacement returns nil when before_code is blank" do
    service = Github::SimpleCodeFixApplier.new(api_client: @api_client, anthropic_key: "test-key")
    file_content = "class Test\n  def foo\n  end\nend"

    result = service.send(:try_direct_replacement, file_content, "", "new code", 4)

    assert_nil result
  end

  test "try_direct_replacement returns nil when after_code is blank" do
    service = Github::SimpleCodeFixApplier.new(api_client: @api_client, anthropic_key: "test-key")
    file_content = "class Test\n  def foo\n  end\nend"

    result = service.send(:try_direct_replacement, file_content, "old code", "", 4)

    assert_nil result
  end

  test "try_direct_replacement finds and replaces matching code" do
    service = Github::SimpleCodeFixApplier.new(api_client: @api_client, anthropic_key: "test-key")
    file_content = <<~RUBY
      class UsersController < ApplicationController
        def show
          @user = User.find(params[:id])
          @user.foo
        end
      end
    RUBY

    result = service.send(:try_direct_replacement, file_content, "@user.foo", "@user&.foo", 4)

    assert result.present?
    assert result[:replacements].present?
    assert_includes result[:replacements].first[:new], "@user&.foo"
  end

  test "try_direct_replacement returns nil when code not found" do
    service = Github::SimpleCodeFixApplier.new(api_client: @api_client, anthropic_key: "test-key")
    file_content = "class Test\n  def foo\n  end\nend"

    result = service.send(:try_direct_replacement, file_content, "nonexistent_code", "new_code", 4)

    assert_nil result
  end

  # normalize_code

  test "normalize_code strips whitespace and normalizes spaces" do
    service = Github::SimpleCodeFixApplier.new(api_client: @api_client, anthropic_key: "test-key")

    result = service.send(:normalize_code, "  foo   bar  ")

    assert_equal "foo bar", result
  end

  test "normalize_code handles nil" do
    service = Github::SimpleCodeFixApplier.new(api_client: @api_client, anthropic_key: "test-key")

    result = service.send(:normalize_code, nil)

    assert_equal "", result
  end

  # extract_referenced_classes

  test "extract_referenced_classes extracts class names from code" do
    service = Github::SimpleCodeFixApplier.new(api_client: @api_client, anthropic_key: "test-key")
    code = "User.find(params[:id])\nProduct.where(active: true)"

    result = service.send(:extract_referenced_classes, code)

    assert_includes result, "User"
    assert_includes result, "Product"
  end

  test "extract_referenced_classes extracts classes from associations" do
    service = Github::SimpleCodeFixApplier.new(api_client: @api_client, anthropic_key: "test-key")
    code = "belongs_to :user\nhas_many :orders"

    result = service.send(:extract_referenced_classes, code)

    assert_includes result, "User"
    assert_includes result, "Order"
  end

  test "extract_referenced_classes excludes common Ruby/Rails classes" do
    service = Github::SimpleCodeFixApplier.new(api_client: @api_client, anthropic_key: "test-key")
    code = "String.new\nActiveRecord::Base"

    result = service.send(:extract_referenced_classes, code)

    refute_includes result, "String"
    refute_includes result, "ActiveRecord"
  end
end
