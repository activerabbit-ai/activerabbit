#!/usr/bin/env ruby
# Simple script to create test data for ActiveRabbit demo

require_relative '../config/environment'

puts "🐰 Creating simple test data for ActiveRabbit..."

# Create a test user first
user = User.create!(
  email: 'test@activerabbit.com',
  password: 'password123',
  password_confirmation: 'password123'
)
puts "✅ User created: #{user.email}"

# Create a test project
project = Project.create!(
  name: 'Test Rails App',
  user: user,
  active: true,
  description: 'Test project for ActiveRabbit demo'
)
puts "✅ Project created: #{project.name} (ID: #{project.id})"

# Create test issues directly
issues_data = [
  {
    exception_class: 'StandardError',
    sample_message: 'This is a test exception for ActiveRabbit',
    controller_action: 'TestController#exception',
    top_frame: 'app/controllers/test_controller.rb:15:in `exception`',
    count: 23,
    status: 'open'
  },
  {
    exception_class: 'NoMethodError',
    sample_message: 'undefined method `invalid_method` for nil:NilClass',
    controller_action: 'UsersController#show',
    top_frame: 'app/controllers/users_controller.rb:42:in `show`',
    count: 8,
    status: 'wip'
  },
  {
    exception_class: 'ActiveRecord::RecordNotFound',
    sample_message: 'Couldn\'t find User with \'id\'=999',
    controller_action: 'UsersController#edit',
    top_frame: 'app/controllers/users_controller.rb:28:in `edit`',
    count: 45,
    status: 'closed'
  }
]

issues_data.each do |issue_data|
  fingerprint = Digest::SHA256.hexdigest("#{issue_data[:exception_class]}:#{issue_data[:top_frame]}:#{issue_data[:controller_action]}")

  issue = Issue.create!(
    project: project,
    fingerprint: fingerprint,
    exception_class: issue_data[:exception_class],
    sample_message: issue_data[:sample_message],
    controller_action: issue_data[:controller_action],
    top_frame: issue_data[:top_frame],
    count: issue_data[:count],
    status: issue_data[:status],
    first_seen_at: 2.hours.ago,
    last_seen_at: 5.minutes.ago
  )

  puts "✅ Created error: #{issue.exception_class} (#{issue.count} occurrences)"
end

puts "🎉 Test data created successfully!"
puts ""
puts "🔗 View errors at: http://localhost:3000/admin/public/errors"
