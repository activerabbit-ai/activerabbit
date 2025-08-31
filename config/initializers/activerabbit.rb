# ActiveRabbit self-monitoring configuration
# This allows the ActiveRabbit app to monitor itself

# Only configure in production and staging environments
if Rails.env.production? || Rails.env.staging?
  # We'll need to create a self-monitoring project and get its API token
  # For now, let's set up the basic configuration structure

  Rails.application.configure do
    config.after_initialize do
      # Check if we have the necessary environment variables for self-monitoring
      if ENV['ACTIVERABBIT_SELF_MONITOR_TOKEN'].present? && ENV['ACTIVERABBIT_SELF_MONITOR_PROJECT_ID'].present?
        begin
          require 'active_rabbit'

          ActiveRabbit::Client.configure do |config|
            config.api_key = ENV['ACTIVERABBIT_SELF_MONITOR_TOKEN']
            config.project_id = ENV['ACTIVERABBIT_SELF_MONITOR_PROJECT_ID']
            config.api_url = "http://localhost:3000"  # Self-monitoring
            config.environment = Rails.env

            # Enable all monitoring features for self-monitoring
            config.enable_performance_monitoring = true
            config.enable_n_plus_one_detection = true
            config.enable_pii_scrubbing = true
          end

          Rails.logger.info "ActiveRabbit self-monitoring initialized for project #{ENV['ACTIVERABBIT_SELF_MONITOR_PROJECT_ID']}"
        rescue => e
          Rails.logger.warn "Failed to initialize ActiveRabbit self-monitoring: #{e.message}"
        end
      else
        Rails.logger.info "ActiveRabbit self-monitoring not configured (missing environment variables)"
      end
    end
  end
elsif Rails.env.development?
  # For development, we can set up self-monitoring if desired
  Rails.application.configure do
    config.after_initialize do
      # Only initialize if we have a self-monitoring project set up
      if ENV['ACTIVERABBIT_SELF_MONITOR_TOKEN'].present? && ENV['ACTIVERABBIT_SELF_MONITOR_PROJECT_ID'].present?
        begin
          require 'active_rabbit'

          ActiveRabbit::Client.configure do |config|
            config.api_key = ENV['ACTIVERABBIT_SELF_MONITOR_TOKEN']
            config.project_id = ENV['ACTIVERABBIT_SELF_MONITOR_PROJECT_ID']
            config.api_url = "http://localhost:3000"  # Self-monitoring
            config.environment = Rails.env

            # Enable monitoring features
            config.enable_performance_monitoring = true
            config.enable_n_plus_one_detection = true
            config.enable_pii_scrubbing = true
          end

          Rails.logger.info "ActiveRabbit self-monitoring initialized in development"
        rescue => e
          Rails.logger.warn "Failed to initialize ActiveRabbit self-monitoring: #{e.message}"
        end
      end
    end
  end
end
