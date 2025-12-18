Rails.application.configure do
  config.lograge.enabled = false if defined?(Lograge)
  config.cache_classes = true
  config.eager_load = true

  config.consider_all_requests_local = true

  config.force_ssl = false

  config.log_level = :debug
  config.active_record.attributes_for_inspect = [:id]
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.log_tags = [:request_id]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)
end
