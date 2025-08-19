#!/usr/bin/env ruby
# Script to create test errors for ActiveRabbit demo

require_relative '../config/environment'

puts "🐰 Creating test data for ActiveRabbit..."

# Create a test project if it doesn't exist
project = Project.find_or_create_by(name: 'Test Rails App') do |p|
  p.active = true
  p.description = 'Test project for ActiveRabbit demo'
end

# Make sure project is saved
project.save! if project.changed?

puts "✅ Project created: #{project.name} (ID: #{project.id})"

# Create some test issues (errors)
test_errors = [
  {
    exception_class: 'StandardError',
    sample_message: 'This is a test exception for ActiveRabbit',
    controller_action: 'TestController#exception',
    top_frame: 'app/controllers/test_controller.rb:15:in `exception`',
    count: 23,
    status: 'open',
    first_seen_at: 2.hours.ago,
    last_seen_at: 5.minutes.ago
  },
  {
    exception_class: 'NoMethodError',
    sample_message: 'undefined method `invalid_method` for nil:NilClass',
    controller_action: 'UsersController#show',
    top_frame: 'app/controllers/users_controller.rb:42:in `show`',
    count: 8,
    status: 'wip',
    first_seen_at: 1.day.ago,
    last_seen_at: 1.hour.ago
  },
  {
    exception_class: 'ActiveRecord::RecordNotFound',
    sample_message: 'Couldn\'t find User with \'id\'=999',
    controller_action: 'UsersController#edit',
    top_frame: 'app/controllers/users_controller.rb:28:in `edit`',
    count: 45,
    status: 'closed',
    first_seen_at: 3.days.ago,
    last_seen_at: 30.minutes.ago
  },
  {
    exception_class: 'ArgumentError',
    sample_message: 'wrong number of arguments (given 1, expected 2)',
    controller_action: 'ReportsController#generate',
    top_frame: 'app/services/report_generator.rb:12:in `generate`',
    count: 3,
    status: 'open',
    first_seen_at: 6.hours.ago,
    last_seen_at: 2.minutes.ago
  }
]

test_errors.each do |error_data|
  # Generate fingerprint
  fingerprint = Issue.generate_fingerprint(
    error_data[:exception_class],
    error_data[:top_frame],
    error_data[:controller_action]
  )

  # Create issue using the project association
  issue = project.issues.create!(
    fingerprint: fingerprint,
    exception_class: error_data[:exception_class],
    sample_message: error_data[:sample_message],
    controller_action: error_data[:controller_action],
    top_frame: error_data[:top_frame],
    count: error_data[:count],
    status: error_data[:status],
    first_seen_at: error_data[:first_seen_at],
    last_seen_at: error_data[:last_seen_at]
  )

  # Create some sample events for each issue
  3.times do |n|
    Event.find_or_create_by(
      issue: issue,
      occurred_at: error_data[:last_seen_at] + n.minutes
    ) do |e|
      e.event_type = 'error'
      e.context = {
        'request_path' => "/#{error_data[:controller_action].split('#').first.underscore}",
        'request_method' => 'GET',
        'user_agent' => 'Mozilla/5.0 (test browser)',
        'environment' => 'development'
      }
      e.user_id = "user_#{rand(1..100)}" if rand < 0.3
    end
  end

  puts "✅ Created error: #{issue.exception_class} (#{issue.count} occurrences)"
end

puts "🎉 Test data created successfully!"
puts ""
puts "🔗 View errors at: http://localhost:3000/admin/public/errors"
puts "🔗 Or with auth at: http://localhost:3000/admin/errors"
