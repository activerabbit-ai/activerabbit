# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# ------------------------------------------------------------
# Development seeds (safe + idempotent)
# ------------------------------------------------------------
return unless Rails.env.development?

puts "[seeds] Seeding development demo data..."

admin_email = "admin@admin.com"
admin_password = ENV.fetch("SEED_ADMIN_PASSWORD", "password123")

account =
  Account.find_or_create_by!(name: "Local Test Account") do |a|
    a.trial_ends_at = 30.days.from_now if a.respond_to?(:trial_ends_at=)
    a.current_plan = "team" if a.respond_to?(:current_plan=)
    a.billing_interval = "month" if a.respond_to?(:billing_interval=)
  end

user =
  User.find_or_initialize_by(email: admin_email).tap do |u|
    u.password = admin_password if u.encrypted_password.blank?
    u.account = account
    u.save!
  end

project =
  Project.find_or_create_by!(account: account, user: user, name: "Local Demo Project") do |p|
    p.slug = "local-demo"
    p.environment = "production"
    p.url = "http://localhost:3000"
    p.active = true if p.respond_to?(:active=)
    p.settings = {} if p.respond_to?(:settings=)
  end

ActsAsTenant.with_tenant(account) do
  # Ensure we have an API token for the demo project
  ApiToken.find_or_create_by!(account: account, project: project, name: "Local Demo Token")

  # Create 10 error events with details
  error_actions = [
    "HomeController#index",
    "ProjectsController#show",
    "ErrorsController#index",
    "PerformanceController#index",
    "SettingsController#index"
  ]

  10.times do |i|
    action = error_actions[i % error_actions.size]
    occurred_at = (i + 1).minutes.ago

    # One issue per controller_action for nicer grouping
    issue = Issue.find_or_create_by!(
      project: project,
      exception_class: "RuntimeError",
      top_frame: "app/controllers/#{action.split('#').first.underscore}.rb:#{10 + i}:in `#{action.split('#').last}'",
      controller_action: action,
      fingerprint: "#{action}:RuntimeError"
    ) do |iss|
      iss.sample_message = "Seeded error for #{action}"
      iss.status = "open" if iss.respond_to?(:status=)
      iss.count = 0 if iss.respond_to?(:count=)
      iss.first_seen_at = occurred_at
      iss.last_seen_at = occurred_at
    end

    # Keep issue counters roughly accurate
    issue.update_columns(
      first_seen_at: [issue.first_seen_at, occurred_at].compact.min,
      last_seen_at: [issue.last_seen_at, occurred_at].compact.max,
      count: (issue.count.to_i + 1)
    ) rescue nil

    Event.create!(
      account: account,
      project: project,
      issue: issue,
      exception_class: "RuntimeError",
      message: "Seeded error ##{i + 1} for #{action}",
      backtrace: [
        "app/controllers/#{action.split('#').first.underscore}.rb:#{10 + i}:in `#{action.split('#').last}'",
        "app/middleware/request_id.rb:12:in `call'"
      ],
      controller_action: action,
      request_method: "GET",
      request_path: "/#{action.split('#').first.underscore.gsub('_controller', '')}",
      environment: "production",
      occurred_at: occurred_at,
      server_name: "localhost",
      request_id: "seed-err-#{i + 1}-#{SecureRandom.hex(6)}",
      context: {
        seeded: true,
        severity: %w[low medium high].sample,
        request: { path: "/#{action}", method: "GET" },
        tags: ["seed", "demo"]
      }
    )
  end

  # Create 20 performance events with details
  perf_targets = [
    "HomeController#index",
    "ProjectsController#show",
    "ErrorsController#show",
    "PerformanceController#action_detail",
    "Api::V1::EventsController#create_error"
  ]

  20.times do |i|
    target = perf_targets[i % perf_targets.size]
    occurred_at = (i + 1).minutes.ago

    # Make durations somewhat realistic; inject a couple slow ones
    duration_ms = if (i % 10).zero?
      2200.0 + rand(0.0..600.0)
    else
      120.0 + rand(0.0..380.0)
    end
    db_ms = (duration_ms * rand(0.15..0.55)).round(1)
    view_ms = (duration_ms * rand(0.05..0.25)).round(1)

    PerformanceEvent.create!(
      account: account,
      project: project,
      target: target,
      duration_ms: duration_ms.round(1),
      db_duration_ms: db_ms,
      view_duration_ms: view_ms,
      allocations: rand(800..8000),
      sql_queries_count: rand(2..45),
      occurred_at: occurred_at,
      environment: "production",
      release_version: "local-seed-#{Date.current}",
      request_method: "GET",
      request_path: "/#{target.split('#').first.underscore.gsub('_controller', '')}",
      server_name: "localhost",
      request_id: "seed-perf-#{i + 1}-#{SecureRandom.hex(6)}",
      context: {
        seeded: true,
        n_plus_one_detected: (i % 9).zero?,
        tags: ["seed", "demo"],
        user: { id_hash: SecureRandom.hex(8) }
      }
    )
  end
end

puts "[seeds] Done. Login: #{admin_email} / #{admin_password} (override with SEED_ADMIN_PASSWORD)."
