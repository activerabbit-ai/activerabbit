Rails.application.configure do
  config.lograge.enabled = false if defined?(Lograge)
  config.cache_classes = true
  config.eager_load = true

  config.consider_all_requests_local = true

  config.force_ssl = false

  config.log_level = :debug
end
