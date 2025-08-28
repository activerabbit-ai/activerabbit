#!/usr/bin/env ruby
# Test script for Slack notification integration

require_relative '../config/environment'

puts "🧪 Testing Slack Integration for ActiveRabbit"
puts "=" * 50

# Find a project to test with - handle multi-tenancy
account = Account.first
unless account
  puts "❌ No accounts found. Please create an account first."
  exit 1
end

ActsAsTenant.current_tenant = account
project = Project.first
unless project
  puts "❌ No projects found. Please create a project first."
  exit 1
end

puts "📋 Testing with project: #{project.name}"

# Check if Slack is configured
if project.slack_configured?
  puts "✅ Slack webhook configured: #{project.slack_webhook_url[0..30]}..."
  puts "📢 Slack channel: #{project.slack_channel}"
  puts "🔔 Notifications enabled: #{project.slack_notifications_enabled?}"
else
  puts "⚠️  Slack not configured for this project"
  puts "   Please configure Slack webhook URL in project settings"
  puts "   Example webhook URL: https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"
  exit 1
end

# Test the Slack service
puts "\n🚀 Testing Slack notification service..."

begin
  slack_service = SlackNotificationService.new(project)

  # Send a test message
  slack_service.send_custom_alert(
    "🧪 *ActiveRabbit Test Notification*",
    "This is a test message to verify that your Slack integration is working correctly!\n\n" +
    "Project: #{project.name}\n" +
    "Environment: #{project.environment}\n" +
    "Timestamp: #{Time.current.strftime('%Y-%m-%d %H:%M:%S UTC')}",
    color: 'good'
  )

  puts "✅ Test notification sent successfully!"
  puts "   Check your Slack channel: #{project.slack_channel}"

rescue StandardError => e
  puts "❌ Failed to send test notification:"
  puts "   Error: #{e.message}"
  puts "   Please check your webhook URL and network connectivity"
  exit 1
end

# Test different alert types if we have data
puts "\n🔍 Testing different alert types..."

# Test with a real issue if available
issue = project.issues.first
if issue
  puts "📊 Testing error frequency alert..."
  begin
    slack_service.send_error_frequency_alert(issue, {
      'count' => 5,
      'time_window' => 10
    })
    puts "✅ Error frequency alert sent"
  rescue StandardError => e
    puts "❌ Error frequency alert failed: #{e.message}"
  end
else
  puts "⚠️  No issues found, skipping error alert test"
end

# Test with a performance event if available
event = project.events.joins(:performance_events).first
if event
  puts "⚡ Testing performance alert..."
  begin
    slack_service.send_performance_alert(event, {
      'duration_ms' => 2500,
      'controller_action' => 'HomeController#index'
    })
    puts "✅ Performance alert sent"
  rescue StandardError => e
    puts "❌ Performance alert failed: #{e.message}"
  end
else
  puts "⚠️  No performance events found, skipping performance alert test"
end

# Test N+1 alert
puts "🔍 Testing N+1 query alert..."
begin
  slack_service.send_n_plus_one_alert({
    'incidents' => [
      {
        'count_in_request' => 15,
        'sql_fingerprint' => {
          'query_type' => 'SELECT'
        }
      },
      {
        'count_in_request' => 8,
        'sql_fingerprint' => {
          'query_type' => 'UPDATE'
        }
      }
    ],
    'controller_action' => 'UsersController#index'
  })
  puts "✅ N+1 query alert sent"
rescue StandardError => e
  puts "❌ N+1 query alert failed: #{e.message}"
end

puts "\n🎉 Slack integration test completed!"
puts "   If you received notifications in your Slack channel, the integration is working correctly."
puts "   You can now configure alert rules to automatically send notifications when issues occur."
