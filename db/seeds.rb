# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "🌱 Seeding database..."

# Create Account
account = Account.find_or_create_by!(name: "Admin Account") do |a|
  a.current_plan = "team"
  a.billing_interval = "month"
  a.trial_ends_at = 14.days.from_now
  a.event_quota = 50_000
  a.events_used_in_period = 0
end
puts "✅ Account: #{account.name} (ID: #{account.id})"

# Create Admin User
user = User.find_or_initialize_by(email: "admin@test.com")
if user.new_record?
  user.password = "admin@test.cuom"
  user.password_confirmation = "admin@admin.com"
  user.account = account
  user.role = "owner"
  user.save!
  puts "✅ User: #{user.email} (password: admin@admin.com)"
else
  puts "✅ User already exists: #{user.email}"
end

# Create Rails App Project
ActsAsTenant.with_tenant(account) do
  project = Project.find_or_create_by!(name: "My Rails App") do |p|
    p.account = account
    p.user = user
    p.slug = "my-rails-app"
    p.url = "http://localhost:3002"
    p.settings = {
      "environment" => "development"
    }
  end
  puts "✅ Project: #{project.name} (slug: #{project.slug})"

  # Create API Token for the project
  api_token = project.api_tokens.find_or_create_by!(name: "Default Token") do |t|
    t.token = SecureRandom.hex(32)
    t.active = true
  end
  puts "✅ API Token: #{api_token.token}"
  puts ""
  puts "=" * 60
  puts "📋 SETUP INSTRUCTIONS"
  puts "=" * 60
  puts ""
  puts "Add this to your Rails app (localhost:3002) Gemfile:"
  puts "  gem 'activerabbit'"
  puts ""
  puts "Add to config/initializers/activerabbit.rb:"
  puts "  ActiveRabbit.configure do |config|"
  puts "    config.api_token = '#{api_token.token}'"
  puts "    config.api_url = 'http://localhost:3000'"
  puts "  end"
  puts ""
  puts "=" * 60
end

puts ""
puts "🎉 Seeding complete!"
puts ""
puts "Login credentials:"
puts "  Email: admin@admin.com"
puts "  Password: admin@admin.com"
puts ""
