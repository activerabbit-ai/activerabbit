ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/autorun"
require "ostruct"

# WebMock for HTTP stubbing (already in Gemfile)
require "webmock/minitest"

# Sidekiq testing mode - prevents Redis connections
require "sidekiq/testing"
Sidekiq::Testing.fake!

# ==============================================================================
# Mock Redis for tests (prevents connection to remote Redis server)
# ==============================================================================
class MockRedis
  def initialize
    @data = {}
  end

  def set(key, value, ex: nil, nx: false)
    if nx && @data.key?(key)
      return false
    end
    @data[key] = { value: value, expires_at: ex ? Time.current + ex : nil }
    true
  end

  def get(key)
    entry = @data[key]
    return nil unless entry
    return nil if entry[:expires_at] && Time.current > entry[:expires_at]
    entry[:value]
  end

  def del(*keys)
    keys.flatten.count { |key| @data.delete(key) }
  end

  def exists?(key)
    entry = @data[key]
    return false unless entry
    return false if entry[:expires_at] && Time.current > entry[:expires_at]
    true
  end

  def keys(pattern = "*")
    @data.keys.select { |k| File.fnmatch(pattern, k) }
  end

  def flushdb
    @data.clear
  end

  def incr(key)
    @data[key] ||= { value: 0, expires_at: nil }
    @data[key][:value] = @data[key][:value].to_i + 1
  end

  def expire(key, seconds)
    return false unless @data.key?(key)
    @data[key][:expires_at] = Time.current + seconds
    true
  end

  def ttl(key)
    entry = @data[key]
    return -2 unless entry
    return -1 unless entry[:expires_at]
    [(entry[:expires_at] - Time.current).to_i, 0].max
  end

  # Support for connection pool interface
  def with
    yield self
  end
end

# Override IssueAlertJob's redis_pool in tests
IssueAlertJob.instance_variable_set(:@redis_pool, MockRedis.new)

# Better test output with stats
require "minitest/pride" if ENV["PRIDE"]

# ==============================================================================
# GLOBAL WebMock Configuration (runs BEFORE any tests, including parallelization)
# ==============================================================================
WebMock.disable_net_connect!(allow_localhost: true)

# Stub common external services globally to prevent issues during parallel worker setup
WebMock.stub_request(:any, /api\.anthropic\.com/).to_return(
  status: 200,
  body: { "content" => [{ "type" => "text", "text" => "AI response" }] }.to_json,
  headers: { "Content-Type" => "application/json" }
)

WebMock.stub_request(:any, /slack\.com/).to_return(
  status: 200, body: '{"ok": true}', headers: { "Content-Type" => "application/json" }
)

WebMock.stub_request(:any, /api\.resend\.com/).to_return(
  status: 200, body: '{"id": "test"}', headers: { "Content-Type" => "application/json" }
)

WebMock.stub_request(:any, /api\.stripe\.com/).to_return(
  status: 200, body: "{}", headers: { "Content-Type" => "application/json" }
)

# ActiveRabbit client (critical: flushes during parallel worker fork)
WebMock.stub_request(:any, /activerabbit\.ai/).to_return(
  status: 200, body: "{}", headers: { "Content-Type" => "application/json" }
)

WebMock.stub_request(:any, /app\.activerabbit\.ai/).to_return(
  status: 200, body: "{}", headers: { "Content-Type" => "application/json" }
)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    # threshold: only parallelize if >50 tests (avoids overhead for small runs)
    # Note: --profile times for first tests in each worker include startup overhead
    parallelize(workers: :number_of_processors, threshold: 50)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order
    fixtures :all

    # Tenant setup for multi-tenancy (similar to spec/support/acts_as_tenant.rb)
    setup do
      @test_account = accounts(:default)
      ActsAsTenant.current_tenant = @test_account
    end

    teardown do
      ActsAsTenant.current_tenant = nil
    end
  end
end

module ActionDispatch
  class IntegrationTest
    include Devise::Test::IntegrationHelpers

    # Tenant setup for integration tests
    setup do
      @test_account = accounts(:default)
      ActsAsTenant.current_tenant = @test_account
    end

    teardown do
      ActsAsTenant.current_tenant = nil
    end
  end
end
