# Disable strict argument validation for complex payloads
Sidekiq.strict_args!(false)

Sidekiq.configure_server do |config|
  # Prefer an explicit Sidekiq Redis URL (writer) if provided to avoid READONLY replica issues.
  url = ENV["SIDEKIQ_REDIS_URL"] || ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
  config.redis = { url: url }
end

Sidekiq.configure_client do |config|
  url = ENV["SIDEKIQ_REDIS_URL"] || ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
  config.redis = { url: url }
end
