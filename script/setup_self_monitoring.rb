#!/usr/bin/env ruby
# Script to set up self-monitoring for the ActiveRabbit application

# This script creates a special project for ActiveRabbit to monitor itself
# and generates the necessary API token

require_relative '../config/environment'

puts "Setting up ActiveRabbit self-monitoring..."

# Find or create a system user for self-monitoring
system_user = User.find_or_create_by(email: 'system@activerabbit.ai') do |user|
  user.password = SecureRandom.hex(32)
  user.password_confirmation = user.password
  # Note: No confirmed_at needed since confirmable is not enabled
end

# Find or create system account
system_account = Account.find_or_create_by(name: 'ActiveRabbit System') do |account|
  # Set any required account attributes
end

# Associate user with system account if not already associated
unless system_user.account == system_account
  system_user.update!(account: system_account)
end

# Set the current tenant to the system account for acts_as_tenant
ActsAsTenant.current_tenant = system_account

# Find or create self-monitoring project
self_monitor_project = system_user.projects.find_or_create_by(name: 'ActiveRabbit Self-Monitor') do |project|
  project.description = 'Internal monitoring project for the ActiveRabbit application itself'
  project.environment = Rails.env
  project.tech_stack = 'rails'
  project.url = 'http://localhost:3000'
  project.active = true
end

# Generate API token if it doesn't exist
api_token = self_monitor_project.api_tokens.active.first
unless api_token
  api_token = self_monitor_project.generate_api_token!
  self_monitor_project.create_default_alert_rules!
end

puts "\n✅ Self-monitoring project created successfully!"
puts "\n📋 Add these environment variables to your .env file or deployment configuration:"
puts "\n# ActiveRabbit Self-Monitoring Configuration"
puts "ACTIVERABBIT_SELF_MONITOR_TOKEN=#{api_token.token}"
puts "ACTIVERABBIT_SELF_MONITOR_PROJECT_ID=#{self_monitor_project.id}"
puts "\n🔧 Project Details:"
puts "  - Project ID: #{self_monitor_project.id}"
puts "  - Project Name: #{self_monitor_project.name}"
puts "  - Environment: #{self_monitor_project.environment}"
puts "  - User: #{system_user.email}"
puts "  - Account: #{system_account.name}"
puts "\n🚀 After adding the environment variables, restart your Rails application to enable self-monitoring."
puts "\n⚠️  Note: The API token above is sensitive. Store it securely and don't commit it to version control."
