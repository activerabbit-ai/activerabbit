require 'spec_helper'
require 'active_support/core_ext/object/blank'
require 'logger'

# Load the class under test without full Rails
require_relative '../../app/services/code_fix_applier'

# Stub Rails.logger for testing
module Rails
  def self.logger
    @logger ||= Logger.new(File::NULL)
  end
end

RSpec.describe CodeFixApplier do
  let(:api_client) { double('GithubApiClient') }
  let(:openai_key) { 'test-key' }
  let(:applier) { described_class.new(api_client: api_client, openai_key: openai_key) }

  describe '#normalize_fixed_code (private)' do
    # Access private method for testing
    def normalize(code)
      applier.send(:normalize_fixed_code, code)
    end

    context 'when removing markdown code blocks' do
      it 'removes ```ruby markers' do
        code = "```ruby\ndef foo\n  bar\nend\n```"
        result = normalize(code)
        expect(result).to include("def foo")
        expect(result).not_to include("```")
      end

      it 'removes ``` markers without language' do
        code = "```\ndef foo\n  bar\nend\n```"
        result = normalize(code)
        expect(result).to include("def foo")
        expect(result).not_to include("```")
      end
    end

    context 'when removing empty lines' do
      it 'removes empty lines at start' do
        code = "\n\n\ndef foo\n  bar\nend"
        result = normalize(code)
        expect(result).to start_with("def foo")
      end

      it 'removes empty lines at end' do
        code = "def foo\n  bar\nend\n\n\n"
        result = normalize(code)
        expect(result).to end_with("end\n").or end_with("end")
      end
    end

    context 'when removing duplicate lines' do
      it 'removes consecutive duplicate lines' do
        code = <<~RUBY
          def foo
            bar = params[:id]
            bar = params[:id]
            baz
          end
        RUBY
        result = normalize(code)
        expect(result.scan('bar = params[:id]').count).to eq(1)
      end

      it 'keeps non-consecutive duplicate lines' do
        code = <<~RUBY
          def foo
            bar = params[:id]
            baz
            bar = params[:id]
          end
        RUBY
        result = normalize(code)
        expect(result.scan('bar = params[:id]').count).to eq(2)
      end

      it 'keeps trivial lines like end' do
        code = <<~RUBY
          def foo
            if condition
            end
          end
        RUBY
        result = normalize(code)
        expect(result.scan('end').count).to eq(2)
      end

      it 'keeps short lines even if duplicated' do
        code = <<~RUBY
          def foo
            x = 1
            x = 1
          end
        RUBY
        result = normalize(code)
        # Short lines (< 10 chars) are kept
        expect(result.scan('x = 1').count).to eq(2)
      end
    end

    context 'when removing duplicate methods' do
      it 'removes duplicate method definitions' do
        code = <<~RUBY
          def handle_payment
            # first version
          end

          def handle_payment
            # duplicate version
          end
        RUBY
        result = normalize(code)
        expect(result.scan('def handle_payment').count).to eq(1)
        expect(result).to include('first version')
        expect(result).not_to include('duplicate version')
      end

      it 'keeps different methods' do
        code = <<~RUBY
          def foo
            # foo logic
          end

          def bar
            # bar logic
          end
        RUBY
        result = normalize(code)
        expect(result).to include('def foo')
        expect(result).to include('def bar')
      end

      it 'handles methods with ? and ! suffixes' do
        code = <<~RUBY
          def valid?
            true
          end

          def valid?
            false
          end
        RUBY
        result = normalize(code)
        expect(result.scan('def valid?').count).to eq(1)
      end
    end

    context 'edge cases' do
      it 'returns nil for blank input' do
        expect(normalize(nil)).to be_nil
        expect(normalize('')).to be_nil
        expect(normalize('   ')).to be_nil
      end

      it 'returns nil for only empty lines' do
        expect(normalize("\n\n\n")).to be_nil
      end
    end
  end

  describe '#has_code_quality_issues (private)' do
    def has_issues?(code)
      applier.send(:has_code_quality_issues, code)
    end

    context 'duplicate method definitions' do
      it 'detects duplicate method definitions' do
        code = <<~RUBY
          class Foo
            def bar
              # first
            end

            def bar
              # second
            end
          end
        RUBY
        expect(has_issues?(code)).to be true
      end

      it 'allows different methods with similar names' do
        code = <<~RUBY
          class Foo
            def bar
              # bar
            end

            def bar!
              # bar!
            end

            def bar?
              # bar?
            end
          end
        RUBY
        expect(has_issues?(code)).to be false
      end
    end

    context 'consecutive duplicate lines' do
      it 'detects consecutive duplicate lines' do
        code = <<~RUBY
          def foo
            subscription_id = @data["subscription"]
            subscription_id = @data["subscription"]
          end
        RUBY
        expect(has_issues?(code)).to be true
      end

      it 'ignores trivial duplicates like end' do
        code = <<~RUBY
          def foo
            if x
            end
          end
        RUBY
        expect(has_issues?(code)).to be false
      end

      it 'ignores short duplicate lines' do
        code = <<~RUBY
          def foo
            x = 1
            x = 1
          end
        RUBY
        # Lines < 10 chars are considered trivial
        expect(has_issues?(code)).to be false
      end

      it 'ignores comment duplicates' do
        code = <<~RUBY
          def foo
            # TODO: fix this
            # TODO: fix this
            bar
          end
        RUBY
        expect(has_issues?(code)).to be false
      end
    end

    context 'missing end statements' do
      it 'detects method without closing end' do
        code = <<~RUBY
          def foo
            bar

          def baz
            qux
          end
        RUBY
        expect(has_issues?(code)).to be true
      end

      it 'allows nested methods at different indentation' do
        code = <<~RUBY
          def foo
            define_method(:bar) do
              # nested
            end
          end
        RUBY
        expect(has_issues?(code)).to be false
      end
    end

    context 'clean code' do
      it 'returns false for well-formed code' do
        code = <<~RUBY
          class PaymentHandler
            def handle_payment_succeeded
              account = account_from_customer
              return unless account

              settings = account.settings || {}
              if settings["past_due"]
                settings.delete("past_due")
                account.update(settings: settings)
              end
            end

            def handle_payment_failed
              account = account_from_customer
              return unless account

              settings = account.settings || {}
              settings["past_due"] = true
              account.update(settings: settings)
            end
          end
        RUBY
        expect(has_issues?(code)).to be false
      end

      it 'returns true for blank content' do
        expect(has_issues?(nil)).to be true
        expect(has_issues?('')).to be true
      end
    end
  end

  describe '#has_duplicate_ends (private)' do
    def has_dup_ends?(code, method_start = 0)
      applier.send(:has_duplicate_ends, code, method_start)
    end

    it 'detects "end end" on same line' do
      code = "def foo\n  bar\nend end\n"
      expect(has_dup_ends?(code)).to be true
    end

    it 'detects consecutive ends at same indentation' do
      code = <<~RUBY
        def foo
          bar
        end
        end
      RUBY
      expect(has_dup_ends?(code)).to be true
    end

    it 'allows nested ends at different indentation' do
      code = <<~RUBY
        def foo
          if bar
            baz
          end
        end
      RUBY
      expect(has_dup_ends?(code)).to be false
    end

    it 'allows class/module end after method end' do
      code = <<~RUBY
        class Foo
          def bar
            baz
          end
        end
      RUBY
      expect(has_dup_ends?(code)).to be false
    end
  end

  describe '#remove_duplicate_methods (private)' do
    def remove_dups(lines)
      applier.send(:remove_duplicate_methods, lines)
    end

    it 'removes second definition of same method' do
      lines = [
        "def foo\n",
        "  first\n",
        "end\n",
        "\n",
        "def foo\n",
        "  second\n",
        "end\n"
      ]
      result = remove_dups(lines)
      expect(result.join).to include('first')
      expect(result.join).not_to include('second')
    end

    it 'keeps all different methods' do
      lines = [
        "def foo\n",
        "  foo_body\n",
        "end\n",
        "def bar\n",
        "  bar_body\n",
        "end\n"
      ]
      result = remove_dups(lines)
      expect(result.join).to include('foo_body')
      expect(result.join).to include('bar_body')
    end

    it 'handles empty input' do
      expect(remove_dups([])).to eq([])
    end

    it 'handles methods with complex bodies' do
      lines = [
        "def process\n",
        "  if condition\n",
        "    do_something\n",
        "  end\n",
        "  result\n",
        "end\n",
        "def process\n",
        "  duplicate\n",
        "end\n"
      ]
      result = remove_dups(lines)
      expect(result.join.scan('def process').count).to eq(1)
      expect(result.join).to include('do_something')
      expect(result.join).not_to include('duplicate')
    end
  end

  describe '#validate_method_structure (private)' do
    def valid_structure?(code)
      applier.send(:validate_method_structure, code)
    end

    it 'returns true for complete method' do
      code = <<~RUBY
        def foo
          bar
        end
      RUBY
      expect(valid_structure?(code)).to be true
    end

    it 'returns false for method without end' do
      code = "def foo\n  bar\n"
      expect(valid_structure?(code)).to be_falsey
    end

    it 'returns false for method without def' do
      code = "  bar\nend\n"
      expect(valid_structure?(code)).to be_falsey
    end

    it 'returns false for blank code' do
      expect(valid_structure?(nil)).to be false
      expect(valid_structure?('')).to be false
    end

    it 'handles nested blocks' do
      code = <<~RUBY
        def foo
          items.each do |item|
            process(item)
          end
        end
      RUBY
      expect(valid_structure?(code)).to be true
    end
  end

  describe '#validate_ruby_syntax (private)' do
    def valid_syntax?(code)
      applier.send(:validate_ruby_syntax, code)
    end

    it 'returns true for valid Ruby' do
      code = <<~RUBY
        def foo
          bar = 1 + 2
          bar
        end
      RUBY
      expect(valid_syntax?(code)).to be true
    end

    it 'returns false for syntax errors' do
      code = <<~RUBY
        def foo
          bar = 1 +
        end
      RUBY
      expect(valid_syntax?(code)).to be false
    end

    it 'returns false for blank code' do
      expect(valid_syntax?(nil)).to be false
      expect(valid_syntax?('')).to be false
    end

    it 'returns true for code with undefined constants' do
      # Syntax is valid even if constants don't exist
      code = <<~RUBY
        def foo
          SomeUndefinedClass.new
        end
      RUBY
      expect(valid_syntax?(code)).to be true
    end
  end

  describe '#extract_method_name_from_fix (private)' do
    def extract_name(code)
      applier.send(:extract_method_name_from_fix, code)
    end

    it 'extracts simple method name' do
      expect(extract_name("def foo\n  bar\nend")).to eq('foo')
    end

    it 'extracts method with self' do
      expect(extract_name("def self.foo\n  bar\nend")).to eq('foo')
    end

    it 'extracts method with ?' do
      expect(extract_name("def valid?\n  true\nend")).to eq('valid?')
    end

    it 'extracts method with !' do
      expect(extract_name("def save!\n  true\nend")).to eq('save!')
    end

    it 'extracts method with =' do
      expect(extract_name("def name=(val)\n  @name = val\nend")).to eq('name=')
    end

    it 'handles indented method definition' do
      expect(extract_name("  def foo\n    bar\n  end")).to eq('foo')
    end

    it 'returns nil for no method' do
      expect(extract_name("foo = bar")).to be_nil
    end
  end

  describe 'integration: applying fixes with quality checks' do
    # Mock the full flow to ensure quality checks prevent bad fixes

    describe 'when fix has duplicate methods' do
      it 'cleans duplicates before applying' do
        original_content = <<~RUBY
          class Handler
            def process
              old_code
            end
          end
        RUBY

        bad_fix = <<~RUBY
          def process
            new_code
          end

          def process
            duplicate_code
          end
        RUBY

        normalized = applier.send(:normalize_fixed_code, bad_fix)
        expect(normalized.scan('def process').count).to eq(1)
        expect(normalized).to include('new_code')
        expect(normalized).not_to include('duplicate_code')
      end
    end

    describe 'when fix has duplicate lines' do
      it 'removes consecutive duplicate lines' do
        bad_fix = <<~RUBY
          def handle_payment_succeeded
            subscription_id = @data["subscription"] || @data.dig("parent", "subscription_details", "subscription")
            subscription_id = @data["subscription"] || @data.dig("parent", "subscription_details", "subscription")
            return unless subscription_id
          end
        RUBY

        normalized = applier.send(:normalize_fixed_code, bad_fix)
        expect(normalized.scan('subscription_id = @data').count).to eq(1)
      end
    end

    describe 'when result would have quality issues' do
      it 'detects the issues in validation' do
        bad_result = <<~RUBY
          class Handler
            def process
              # first
            end

            def process
              # second - duplicate!
            end
          end
        RUBY

        expect(applier.send(:has_code_quality_issues, bad_result)).to be true
      end
    end
  end

  describe 'real-world scenarios' do
    describe 'Stripe handler duplicate fix' do
      it 'handles the exact scenario from the bug report' do
        # This is the problematic code pattern reported
        bad_fix = <<~RUBY
          def handle_payment_succeeded
              account = account_from_customer
              return unless account
              settings = account.settings || {}
              if settings["past_due"]
                settings.delete("past_due")
                account.update(settings: settings)
              end

          def handle_payment_succeeded
              # Also upsert Pay::Subscription using the invoice's subscription id
              subscription_id = if @data.respond_to?(:subscription)
                @data.subscription
              else
                @data["subscription"] || @data.dig("parent", "subscription_details", "subscription")
                @data["subscription"] || @data["parent"] && @data["parent"]["subscription_details"] && @data["parent"]["subscription_details"]["subscription"]
              end
              return unless subscription_id

              begin
                sub = Stripe::Subscription.retrieve(subscription_id)
                sub = Stripe::Subscription.retrieve(subscription_id)
                original_data = @data
                @data = sub
                sync_subscription
              ensure
                @data = original_data
              end
            end
        RUBY

        # After normalization, should have only one method and no duplicate lines
        normalized = applier.send(:normalize_fixed_code, bad_fix)

        expect(normalized.scan('def handle_payment_succeeded').count).to eq(1)
        expect(normalized.scan('Stripe::Subscription.retrieve').count).to eq(1)

        # Quality check should pass after normalization
        expect(applier.send(:has_code_quality_issues, normalized)).to be false
      end
    end

    describe 'ERB file fix' do
      it 'does not apply Ruby method logic to ERB' do
        erb_fix = '<%= product.name %>'
        # ERB content should pass through normalize without being treated as Ruby method
        normalized = applier.send(:normalize_fixed_code, erb_fix)
        expect(normalized).to include('product.name')
      end
    end
  end
end
