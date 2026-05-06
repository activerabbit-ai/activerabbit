require "test_helper"

class AnalyzeIssueJobTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    @project = projects(:default)
    ActsAsTenant.current_tenant = @account
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def make_issue(attrs = {})
    Issue.create!({
      account_id: @account.id, project_id: @project.id,
      fingerprint: Digest::SHA256.hexdigest("fp-#{SecureRandom.hex(4)}"),
      exception_class: "RuntimeError", top_frame: "x:1",
      controller_action: "X#y", status: "open", count: 1,
      first_seen_at: 1.hour.ago, last_seen_at: 5.minutes.ago
    }.merge(attrs))
  end

  # ── Guard branches: no Analyzer call should happen ───────────────────

  test "skips when issue is already analyzed" do
    issue = make_issue(sre_analyzed_at: Time.current)
    refute calls_analyzer?(issue.id, api_key: "sk-test", over_quota: false)
  end

  test "tolerates a missing issue id" do
    refute calls_analyzer?(999_999_999, api_key: "sk-test", over_quota: false)
  end

  test "skips when ANTHROPIC_API_KEY is blank" do
    issue = make_issue
    refute calls_analyzer?(issue.id, api_key: "", over_quota: false)
  end

  test "skips when over hourly quota" do
    issue = make_issue
    refute calls_analyzer?(issue.id, api_key: "sk-test", over_quota: true)
  end

  # ── Happy path: Analyzer is invoked exactly once ────────────────────

  test "invokes the analyzer when all preconditions pass" do
    issue = make_issue
    assert calls_analyzer?(issue.id, api_key: "sk-test", over_quota: false)
  end

  private

  # Records whether SreInbox::Analyzer#call is reached. Stubs out the
  # quota check (no Redis) and the analyzer's network call.
  def calls_analyzer?(issue_id, api_key:, over_quota:)
    called = false
    quota_lambda = ->(_account_id) { !over_quota }

    AnalyzeIssueJob.stub_any_instance(:within_account_quota?, quota_lambda) do
      SreInbox::Analyzer.stub_any_instance(:call, -> { called = true; { ok: true } }) do
        with_env("ANTHROPIC_API_KEY" => api_key) do
          AnalyzeIssueJob.new.perform(issue_id)
        end
      end
    end
    called
  end

  def with_env(pairs)
    original = pairs.transform_values { |_| nil }
    pairs.each_key { |k| original[k] = ENV[k] }
    pairs.each     { |k, v| ENV[k] = v }
    yield
  ensure
    original.each   { |k, v| ENV[k] = v }
  end
end

# Minimal `stub_any_instance` shim using built-in Minitest::Mock-style stubbing.
# Avoids pulling in Mocha for two callsites.
class Class
  def stub_any_instance(method, value_or_lambda)
    original = instance_method(method) rescue nil
    define_method(method) do |*args|
      value_or_lambda.respond_to?(:call) ? value_or_lambda.call(*args) : value_or_lambda
    end
    yield
  ensure
    if original
      define_method(method, original)
    else
      remove_method(method) if instance_methods(false).include?(method)
    end
  end
end
