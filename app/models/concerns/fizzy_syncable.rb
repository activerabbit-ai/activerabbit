# frozen_string_literal: true

# FizzySyncable concern handles Fizzy board integration settings
# for syncing errors to external Fizzy boards.
#
# Configuration can be set via environment variables (preferred for production)
# or stored in the project's settings JSON column.
#
# Environment variables (checked first):
#   FIZZY_ENDPOINT_URL_{PROJECT_SLUG} - Project-specific endpoint
#   FIZZY_ENDPOINT_URL                - Global fallback endpoint
#   FIZZY_API_KEY_{PROJECT_SLUG}      - Project-specific API key
#   FIZZY_API_KEY                     - Global fallback API key
#
# Usage:
#   project.fizzy_configured?      # => true if endpoint and API key are set
#   project.fizzy_sync_enabled?    # => true if configured and not disabled
#   project.enable_fizzy_sync!     # Enable syncing
#   project.disable_fizzy_sync!    # Disable syncing
#
module FizzySyncable
  extend ActiveSupport::Concern

  # Get the Fizzy endpoint URL
  # Priority: ENV variable > database setting
  def fizzy_endpoint_url
    env_endpoint = ENV["FIZZY_ENDPOINT_URL_#{slug.upcase}"] || ENV["FIZZY_ENDPOINT_URL"]
    env_endpoint.presence || settings["fizzy_endpoint_url"]
  end

  # Set the Fizzy endpoint URL in settings
  # Supports "ENV:VAR_NAME" format to store reference to environment variable
  def fizzy_endpoint_url=(url)
    if url.present? && !url.start_with?("ENV:")
      self.settings = settings.merge("fizzy_endpoint_url" => url.strip)
    elsif url&.start_with?("ENV:")
      env_var = url.sub("ENV:", "")
      self.settings = settings.merge("fizzy_endpoint_url" => "ENV:#{env_var}")
    else
      new_settings = settings.dup
      new_settings.delete("fizzy_endpoint_url")
      self.settings = new_settings
    end
  end

  # Check if endpoint URL comes from environment variable
  def fizzy_endpoint_from_env?
    settings["fizzy_endpoint_url"]&.start_with?("ENV:") ||
      ENV["FIZZY_ENDPOINT_URL_#{slug.upcase}"].present? ||
      ENV["FIZZY_ENDPOINT_URL"].present?
  end

  # Get the Fizzy API key
  # Priority: ENV variable > database setting
  def fizzy_api_key
    env_key = ENV["FIZZY_API_KEY_#{slug.upcase}"] || ENV["FIZZY_API_KEY"]
    env_key.presence || settings["fizzy_api_key"]
  end

  # Set the Fizzy API key in settings
  # Supports "ENV:VAR_NAME" format to store reference to environment variable
  def fizzy_api_key=(key)
    if key.present? && !key.start_with?("ENV:")
      self.settings = settings.merge("fizzy_api_key" => key.strip)
    elsif key&.start_with?("ENV:")
      env_var = key.sub("ENV:", "")
      self.settings = settings.merge("fizzy_api_key" => "ENV:#{env_var}")
    else
      new_settings = settings.dup
      new_settings.delete("fizzy_api_key")
      self.settings = new_settings
    end
  end

  # Check if API key comes from environment variable
  def fizzy_api_key_from_env?
    settings["fizzy_api_key"]&.start_with?("ENV:") ||
      ENV["FIZZY_API_KEY_#{slug.upcase}"].present? ||
      ENV["FIZZY_API_KEY"].present?
  end

  # Check if Fizzy integration is configured (has both endpoint and API key)
  def fizzy_configured?
    fizzy_endpoint_url.present? && fizzy_api_key.present?
  end

  # Check if Fizzy sync is enabled (configured and not explicitly disabled)
  def fizzy_sync_enabled?
    fizzy_configured? && settings["fizzy_sync_enabled"] != false
  end

  # Enable Fizzy sync for this project
  def enable_fizzy_sync!
    self.settings = settings.merge("fizzy_sync_enabled" => true)
    save!
  end

  # Disable Fizzy sync for this project
  def disable_fizzy_sync!
    self.settings = settings.merge("fizzy_sync_enabled" => false)
    save!
  end
end
