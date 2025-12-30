source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Authentication
gem "devise"
gem 'omniauth-github'
gem 'omniauth-google-oauth2'

# Background jobs
gem "sidekiq"
gem "sidekiq-cron"

# Redis for caching and Sidekiq
gem "redis", ">= 4.0.1"

# Pagination
gem "pagy", "~> 9.0"

# Billing & subscriptions
gem "pay", "~> 8.0"
gem "stripe", "~> 13.0"

# Administrate from GitHub (Rails 8 compatibility)
gem "administrate", github: "thoughtbot/administrate"

# Multi-tenancy
gem "acts_as_tenant"

# UI styling
gem "tailwindcss-rails"

# Security
gem "rack-attack"

# HTTP client
gem "faraday"

# GitHub App JWT
gem "jwt", "~> 2.8"

# Slack notifications
gem "slack-notifier"

# Metrics
gem "HDRHistogram"

# Environment management
gem "dotenv-rails"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

gem 'ransack'

gem 'slack-ruby-client'

# Resend email delivery service
gem 'resend'

# Authorization with Pundit
gem 'pundit'

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # RSpec testing framework
  gem "rspec-rails", "~> 6.0"
  gem "rails-controller-testing"
  gem "factory_bot_rails"
  gem "faker"
  gem "shoulda-matchers"
  gem "climate_control"
end

# ActiveRabbit AI monitoring gem
gem "activerabbit-ai", "~> 0.5.2"

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
  gem "bullet", "~> 7.2", require: false
  gem "rack-mini-profiler", "~> 3.3"

  # Preview emails in browser
  gem "letter_opener"
end
