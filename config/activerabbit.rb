ActiveRabbit::Client.configure do |config|
  config.api_key = "5a8e3ccb97f95a2a8e77699a15cd55657d5fd6fcba321ed3231930987d4e9524"

  # Enable monitoring features
  config.enable_performance_monitoring = true
  config.enable_n_plus_one_detection   = true
  config.enable_pii_scrubbing          = true

  # Optional: enable deployment tracking
  config.revision = ENV["APP_REVISION"] || `git rev-parse HEAD`.chomp

  # Optional: 404 handling (true = ignore 404s, false = report them)
  config.ignore_404 = true
end
