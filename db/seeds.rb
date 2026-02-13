# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "Seeding database..."

# ---------------------------------------------------------------------------
# Account
# ---------------------------------------------------------------------------
account = Account.find_or_create_by!(name: "Acme Corp") do |a|
  a.current_plan = "team"
  a.billing_interval = "month"
  a.trial_ends_at = 14.days.from_now
  a.event_quota = 50_000
  a.events_used_in_period = 0
end
puts "  Account: #{account.name} (ID: #{account.id})"

# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------
users_data = [
  { email: "admin@activerabbit.com",    password: "password123", role: "owner"  },
  { email: "dev@activerabbit.com",      password: "password123", role: "member" },
  { email: "qa@activerabbit.com",       password: "password123", role: "member" },
  { email: "frontend@activerabbit.com", password: "password123", role: "member" }
]

users = users_data.map do |attrs|
  user = User.find_or_initialize_by(email: attrs[:email])
  if user.new_record?
    user.password              = attrs[:password]
    user.password_confirmation = attrs[:password]
    user.account               = account
    user.role                  = attrs[:role]
    user.confirmed_at          = Time.current
    user.save!
    puts "  Created user: #{user.email} (#{user.role})"
  else
    puts "  User exists:  #{user.email}"
  end
  user
end

admin_user = users.first

# Make admin@activerabbit.com a super admin
unless admin_user.super_admin?
  admin_user.update!(super_admin: true)
  puts "  Promoted #{admin_user.email} to super_admin"
end

# ---------------------------------------------------------------------------
# Projects
# ---------------------------------------------------------------------------
ActsAsTenant.with_tenant(account) do
  projects_data = [
    { name: "Acme Web App",   slug: "acme-web",   url: "https://app.acme.com",  environment: "production"  },
    { name: "Acme API",       slug: "acme-api",    url: "https://api.acme.com",  environment: "production"  },
    { name: "Acme Admin",     slug: "acme-admin",  url: "https://admin.acme.com", environment: "staging"    }
  ]

  projects = projects_data.map do |attrs|
    project = Project.find_or_create_by!(name: attrs[:name]) do |p|
      p.account     = account
      p.user        = admin_user
      p.slug        = attrs[:slug]
      p.url         = attrs[:url]
      p.environment = attrs[:environment]
      p.settings    = { "environment" => attrs[:environment] }
    end
    puts "  Project: #{project.name} (#{project.slug})"

    # Create API token for each project
    token = project.api_tokens.find_or_create_by!(name: "Default Token") do |t|
      t.token  = SecureRandom.hex(32)
      t.active = true
    end
    puts "    Token: #{token.token}"

    project
  end

  web_app, api_app, admin_app = projects

  # ---------------------------------------------------------------------------
  # Errors / Events
  # ---------------------------------------------------------------------------
  puts "\n  Seeding error events..."

  # Helper: base context for regular HTTP requests
  def base_context
    { "ruby_version" => "3.4.8", "rails_version" => "8.0.2.1" }
  end

  # Helper: context that marks an event as a Sidekiq job failure
  def sidekiq_context(worker_class, queue: "default", retry_count: 0)
    base_context.merge(
      "job_context" => {
        "worker_class" => worker_class,
        "queue"        => queue,
        "retry_count"  => retry_count
      },
      "tags" => { "component" => "sidekiq" }
    )
  end

  # Helper: context that marks an event as an ActiveJob failure
  def activejob_context(job_class, queue: "default")
    base_context.merge(
      "job" => {
        "class"    => job_class,
        "queue"    => queue,
        "provider" => "solid_queue"
      },
      "tags" => { "component" => "active_job" }
    )
  end

  # =========================================================================
  # OPEN issues -- currently active errors
  # =========================================================================
  error_scenarios = [
    # --- Web App: open issues ---
    {
      project: web_app,
      exception_class: "ActiveRecord::RecordNotFound",
      message: "Couldn't find User with 'id'=99942",
      backtrace: [
        "app/controllers/users_controller.rb:14:in `show'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'",
        "actionpack (8.0.2.1) lib/abstract_controller/base.rb:226:in `process_action'",
        "actionpack (8.0.2.1) lib/action_controller/metal/rendering.rb:193:in `process_action'"
      ],
      controller_action: "UsersController#show",
      request_path: "/users/99942",
      request_method: "GET",
      occurrences: 47,
      first_seen: 5.days.ago,
      environment: "production",
      server_name: "web-01",
      context: base_context
    },
    {
      project: web_app,
      exception_class: "ActionController::ParameterMissing",
      message: "param is missing or the value is empty: order",
      backtrace: [
        "app/controllers/orders_controller.rb:42:in `order_params'",
        "app/controllers/orders_controller.rb:18:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "OrdersController#create",
      request_path: "/orders",
      request_method: "POST",
      occurrences: 12,
      first_seen: 3.days.ago,
      environment: "production",
      server_name: "web-02",
      context: base_context
    },
    {
      project: web_app,
      exception_class: "NoMethodError",
      message: "undefined method `name' for nil:NilClass",
      backtrace: [
        "app/views/dashboard/index.html.erb:23:in `_app_views_dashboard_index_html_erb__1234'",
        "actionview (8.0.2.1) lib/action_view/template.rb:278:in `block in render'",
        "activesupport (8.0.2.1) lib/active_support/notifications.rb:212:in `instrument'"
      ],
      controller_action: "DashboardController#index",
      request_path: "/dashboard",
      request_method: "GET",
      occurrences: 83,
      first_seen: 7.days.ago,
      environment: "production",
      server_name: "web-01",
      context: base_context
    },
    {
      project: web_app,
      exception_class: "Timeout::Error",
      message: "execution expired",
      backtrace: [
        "app/services/external_api_client.rb:55:in `fetch_recommendations'",
        "app/controllers/products_controller.rb:30:in `show'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "ProductsController#show",
      request_path: "/products/fancy-widget",
      request_method: "GET",
      occurrences: 19,
      first_seen: 2.days.ago,
      environment: "production",
      server_name: "web-02",
      context: base_context
    },

    # --- API: open issues ---
    {
      project: api_app,
      exception_class: "JWT::DecodeError",
      message: "Signature has expired",
      backtrace: [
        "app/middleware/jwt_auth.rb:22:in `decode_token'",
        "app/middleware/jwt_auth.rb:10:in `call'",
        "actionpack (8.0.2.1) lib/action_dispatch/middleware/executor.rb:14:in `call'"
      ],
      controller_action: "JwtAuth#call",
      request_path: "/api/v1/me",
      request_method: "GET",
      occurrences: 156,
      first_seen: 10.days.ago,
      environment: "production",
      server_name: "api-01",
      context: base_context
    },
    {
      project: api_app,
      exception_class: "ActiveRecord::RecordInvalid",
      message: "Validation failed: Email has already been taken",
      backtrace: [
        "app/controllers/api/v1/registrations_controller.rb:15:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "Api::V1::RegistrationsController#create",
      request_path: "/api/v1/register",
      request_method: "POST",
      occurrences: 29,
      first_seen: 6.days.ago,
      environment: "production",
      server_name: "api-02",
      context: base_context
    },
    {
      project: api_app,
      exception_class: "ArgumentError",
      message: "invalid date: '2025-13-45'",
      backtrace: [
        "app/controllers/api/v1/reports_controller.rb:28:in `parse_date_range'",
        "app/controllers/api/v1/reports_controller.rb:8:in `index'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "Api::V1::ReportsController#index",
      request_path: "/api/v1/reports?start=2025-13-45",
      request_method: "GET",
      occurrences: 15,
      first_seen: 4.days.ago,
      environment: "production",
      server_name: "api-02",
      context: base_context
    },

    # --- Admin / Staging: open issues ---
    {
      project: admin_app,
      exception_class: "ActionView::Template::Error",
      message: "undefined local variable or method `current_admin' for #<ActionView::Base>",
      backtrace: [
        "app/views/admin/layouts/application.html.erb:18:in `_app_views_admin_layouts_application_html_erb__5678'",
        "actionview (8.0.2.1) lib/action_view/template.rb:278:in `block in render'"
      ],
      controller_action: "Admin::UsersController#index",
      request_path: "/admin/users",
      request_method: "GET",
      occurrences: 22,
      first_seen: 3.days.ago,
      environment: "staging",
      server_name: "staging-01",
      context: base_context
    }
  ]

  # =========================================================================
  # CLOSED issues -- resolved errors (older, no longer firing)
  # =========================================================================
  closed_scenarios = [
    {
      project: web_app,
      exception_class: "ActiveRecord::ConnectionTimeoutError",
      message: "could not obtain a connection from the pool within 5.000 seconds; all pooled connections were in use",
      backtrace: [
        "app/controllers/search_controller.rb:12:in `index'",
        "activerecord (8.0.2.1) lib/active_record/connection_adapters/abstract/connection_pool.rb:295:in `checkout'"
      ],
      controller_action: "SearchController#index",
      request_path: "/search?q=widgets",
      request_method: "GET",
      occurrences: 34,
      first_seen: 20.days.ago,
      last_seen: 12.days.ago,
      environment: "production",
      server_name: "web-01",
      context: base_context
    },
    {
      project: api_app,
      exception_class: "ActionController::RoutingError",
      message: "No route matches [GET] \"/api/v1/userz\"",
      backtrace: [
        "actionpack (8.0.2.1) lib/action_dispatch/middleware/debug_exceptions.rb:72:in `call'",
        "actionpack (8.0.2.1) lib/action_dispatch/middleware/show_exceptions.rb:24:in `call'"
      ],
      controller_action: "ActionController::RoutingError",
      request_path: "/api/v1/userz",
      request_method: "GET",
      occurrences: 8,
      first_seen: 30.days.ago,
      last_seen: 25.days.ago,
      environment: "production",
      server_name: "api-01",
      context: base_context
    },
    {
      project: web_app,
      exception_class: "Net::OpenTimeout",
      message: "execution expired - connect(2) for \"smtp.sendgrid.net\" port 587",
      backtrace: [
        "app/mailers/notification_mailer.rb:8:in `welcome_email'",
        "app/jobs/send_welcome_email_job.rb:6:in `perform'",
        "activejob (8.0.2.1) lib/active_job/execution.rb:53:in `perform_now'"
      ],
      controller_action: "SendWelcomeEmailJob#perform",
      request_path: nil,
      request_method: nil,
      occurrences: 15,
      first_seen: 18.days.ago,
      last_seen: 14.days.ago,
      environment: "production",
      server_name: "worker-01",
      context: activejob_context("SendWelcomeEmailJob", queue: "mailers")
    },
    {
      project: admin_app,
      exception_class: "NameError",
      message: "uninitialized constant AdminDashboardHelper",
      backtrace: [
        "app/controllers/admin/dashboard_controller.rb:3:in `index'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "Admin::DashboardController#index",
      request_path: "/admin",
      request_method: "GET",
      occurrences: 4,
      first_seen: 15.days.ago,
      last_seen: 10.days.ago,
      environment: "staging",
      server_name: "staging-01",
      context: base_context
    }
  ]

  # =========================================================================
  # RECENT 24h -- errors that fired in the last 24 hours
  # =========================================================================
  recent_scenarios = [
    {
      project: web_app,
      exception_class: "Redis::TimeoutError",
      message: "Connection timed out after 5.0 seconds",
      backtrace: [
        "app/services/cache_service.rb:18:in `fetch_user_preferences'",
        "app/controllers/settings_controller.rb:8:in `index'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "SettingsController#index",
      request_path: "/settings",
      request_method: "GET",
      occurrences: 11,
      environment: "production",
      server_name: "web-03",
      context: base_context
    },
    {
      project: api_app,
      exception_class: "Faraday::ConnectionFailed",
      message: "Failed to open TCP connection to payments.stripe.com:443",
      backtrace: [
        "app/services/payment_gateway.rb:45:in `charge'",
        "app/controllers/api/v1/payments_controller.rb:20:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "Api::V1::PaymentsController#create",
      request_path: "/api/v1/payments",
      request_method: "POST",
      occurrences: 8,
      environment: "production",
      server_name: "api-01",
      context: base_context
    },
    {
      project: web_app,
      exception_class: "TypeError",
      message: "no implicit conversion of nil into String",
      backtrace: [
        "app/services/csv_exporter.rb:42:in `generate_row'",
        "app/services/csv_exporter.rb:18:in `block in export'",
        "app/controllers/exports_controller.rb:11:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "ExportsController#create",
      request_path: "/exports",
      request_method: "POST",
      occurrences: 5,
      environment: "production",
      server_name: "web-01",
      context: base_context
    },
    {
      project: web_app,
      exception_class: "RuntimeError",
      message: "Stripe webhook signature verification failed",
      backtrace: [
        "app/controllers/webhooks/stripe_controller.rb:15:in `verify_signature!'",
        "app/controllers/webhooks/stripe_controller.rb:5:in `create'",
        "actionpack (8.0.2.1) lib/action_controller/metal/basic_implicit_render.rb:6:in `send_action'"
      ],
      controller_action: "Webhooks::StripeController#create",
      request_path: "/webhooks/stripe",
      request_method: "POST",
      occurrences: 3,
      environment: "production",
      server_name: "web-02",
      context: base_context
    }
  ]

  # =========================================================================
  # FAILED JOBS -- background job errors (Sidekiq + ActiveJob)
  # =========================================================================
  job_scenarios = [
    {
      project: web_app,
      exception_class: "PG::ConnectionBad",
      message: "could not connect to server: Connection refused",
      backtrace: [
        "app/models/report.rb:34:in `generate_daily'",
        "app/jobs/daily_report_job.rb:10:in `perform'",
        "activejob (8.0.2.1) lib/active_job/execution.rb:53:in `perform_now'"
      ],
      controller_action: "DailyReportJob#perform",
      request_path: nil,
      request_method: nil,
      occurrences: 7,
      first_seen: 2.days.ago,
      environment: "production",
      server_name: "worker-01",
      context: activejob_context("DailyReportJob", queue: "default")
    },
    {
      project: web_app,
      exception_class: "Sidekiq::JobRetry::Handled",
      message: "Exceeded 25 retries for InvoiceGeneratorWorker",
      backtrace: [
        "app/workers/invoice_generator_worker.rb:18:in `perform'",
        "sidekiq (8.0.7) lib/sidekiq/processor.rb:199:in `execute_job'",
        "sidekiq (8.0.7) lib/sidekiq/processor.rb:170:in `process'"
      ],
      controller_action: "InvoiceGeneratorWorker#perform",
      request_path: nil,
      request_method: nil,
      occurrences: 25,
      first_seen: 4.days.ago,
      environment: "production",
      server_name: "worker-02",
      context: sidekiq_context("InvoiceGeneratorWorker", queue: "billing", retry_count: 25)
    },
    {
      project: api_app,
      exception_class: "Net::SMTPAuthenticationError",
      message: "535 5.7.8 Authentication credentials invalid",
      backtrace: [
        "app/mailers/transactional_mailer.rb:12:in `receipt'",
        "app/jobs/send_receipt_job.rb:8:in `perform'",
        "activejob (8.0.2.1) lib/active_job/execution.rb:53:in `perform_now'"
      ],
      controller_action: "SendReceiptJob#perform",
      request_path: nil,
      request_method: nil,
      occurrences: 42,
      first_seen: 3.days.ago,
      environment: "production",
      server_name: "worker-01",
      context: activejob_context("SendReceiptJob", queue: "mailers")
    },
    {
      project: web_app,
      exception_class: "Errno::ENOENT",
      message: "No such file or directory @ rb_sysopen - /tmp/exports/report_20260210.csv",
      backtrace: [
        "app/workers/csv_upload_worker.rb:14:in `perform'",
        "sidekiq (8.0.7) lib/sidekiq/processor.rb:199:in `execute_job'",
        "sidekiq (8.0.7) lib/sidekiq/processor.rb:170:in `process'"
      ],
      controller_action: "CsvUploadWorker#perform",
      request_path: nil,
      request_method: nil,
      occurrences: 9,
      first_seen: 1.day.ago,
      environment: "production",
      server_name: "worker-01",
      context: sidekiq_context("CsvUploadWorker", queue: "exports", retry_count: 3)
    },
    {
      project: api_app,
      exception_class: "Redis::CommandError",
      message: "MISCONF Redis is configured to save RDB snapshots, but it is currently not able to persist on disk",
      backtrace: [
        "app/workers/analytics_aggregator_worker.rb:22:in `aggregate'",
        "app/workers/analytics_aggregator_worker.rb:8:in `perform'",
        "sidekiq (8.0.7) lib/sidekiq/processor.rb:199:in `execute_job'"
      ],
      controller_action: "AnalyticsAggregatorWorker#perform",
      request_path: nil,
      request_method: nil,
      occurrences: 18,
      first_seen: 6.hours.ago,
      environment: "production",
      server_name: "worker-02",
      context: sidekiq_context("AnalyticsAggregatorWorker", queue: "analytics", retry_count: 5)
    },
    {
      project: web_app,
      exception_class: "ActiveJob::DeserializationError",
      message: "Error while trying to deserialize arguments: Couldn't find Order with 'id'=784512",
      backtrace: [
        "activejob (8.0.2.1) lib/active_job/arguments.rb:85:in `deserialize_argument'",
        "app/jobs/order_confirmation_job.rb:5:in `perform'",
        "activejob (8.0.2.1) lib/active_job/execution.rb:53:in `perform_now'"
      ],
      controller_action: "OrderConfirmationJob#perform",
      request_path: nil,
      request_method: nil,
      occurrences: 14,
      first_seen: 2.days.ago,
      environment: "production",
      server_name: "worker-01",
      context: activejob_context("OrderConfirmationJob", queue: "default")
    }
  ]

  # ---------------------------------------------------------------------------
  # Ingest all events
  # ---------------------------------------------------------------------------
  total_events = 0

  # -- Open issues (spread across their time range) --
  error_scenarios.each do |scenario|
    scenario[:occurrences].times do
      spread   = scenario[:first_seen]..Time.current
      occurred = rand(spread)

      Event.ingest_error(
        project: scenario[:project],
        payload: {
          exception_class:   scenario[:exception_class],
          message:           scenario[:message],
          backtrace:         scenario[:backtrace],
          controller_action: scenario[:controller_action],
          request_path:      scenario[:request_path],
          request_method:    scenario[:request_method],
          occurred_at:       occurred,
          environment:       scenario[:environment],
          server_name:       scenario[:server_name],
          request_id:        SecureRandom.uuid,
          user_id:           users.sample.id.to_s,
          context:           scenario[:context]
        }
      )
      total_events += 1
    end
    puts "    [open]   #{scenario[:exception_class]} in #{scenario[:controller_action]} (x#{scenario[:occurrences]})"
  end

  # -- Closed issues (old, resolved) --
  closed_scenarios.each do |scenario|
    scenario[:occurrences].times do
      spread   = scenario[:first_seen]..scenario[:last_seen]
      occurred = rand(spread)

      Event.ingest_error(
        project: scenario[:project],
        payload: {
          exception_class:   scenario[:exception_class],
          message:           scenario[:message],
          backtrace:         scenario[:backtrace],
          controller_action: scenario[:controller_action],
          request_path:      scenario[:request_path],
          request_method:    scenario[:request_method],
          occurred_at:       occurred,
          environment:       scenario[:environment],
          server_name:       scenario[:server_name],
          request_id:        SecureRandom.uuid,
          user_id:           users.sample.id.to_s,
          context:           scenario[:context]
        }
      )
      total_events += 1
    end
    puts "    [closed] #{scenario[:exception_class]} in #{scenario[:controller_action]} (x#{scenario[:occurrences]})"
  end

  # Mark closed issues
  closed_scenarios.each do |scenario|
    Issue.where(
      project: scenario[:project],
      exception_class: scenario[:exception_class],
      controller_action: scenario[:controller_action]
    ).find_each do |issue|
      issue.update!(status: "closed", closed_at: scenario[:last_seen] + 1.hour)
    end
  end

  # -- Recent 24h issues (all events within the last 24 hours) --
  recent_scenarios.each do |scenario|
    scenario[:occurrences].times do
      occurred = rand(24.hours.ago..Time.current)

      Event.ingest_error(
        project: scenario[:project],
        payload: {
          exception_class:   scenario[:exception_class],
          message:           scenario[:message],
          backtrace:         scenario[:backtrace],
          controller_action: scenario[:controller_action],
          request_path:      scenario[:request_path],
          request_method:    scenario[:request_method],
          occurred_at:       occurred,
          environment:       scenario[:environment],
          server_name:       scenario[:server_name],
          request_id:        SecureRandom.uuid,
          user_id:           users.sample.id.to_s,
          context:           scenario[:context]
        }
      )
      total_events += 1
    end
    puts "    [24h]    #{scenario[:exception_class]} in #{scenario[:controller_action]} (x#{scenario[:occurrences]})"
  end

  # -- Failed jobs (background job errors with job context) --
  job_scenarios.each do |scenario|
    first = scenario[:first_seen] || 2.days.ago

    scenario[:occurrences].times do
      spread   = first..Time.current
      occurred = rand(spread)

      Event.ingest_error(
        project: scenario[:project],
        payload: {
          exception_class:   scenario[:exception_class],
          message:           scenario[:message],
          backtrace:         scenario[:backtrace],
          controller_action: scenario[:controller_action],
          request_path:      scenario[:request_path],
          request_method:    scenario[:request_method],
          occurred_at:       occurred,
          environment:       scenario[:environment],
          server_name:       scenario[:server_name],
          request_id:        SecureRandom.uuid,
          user_id:           nil,
          context:           scenario[:context]
        }
      )
      total_events += 1
    end
    puts "    [job]    #{scenario[:exception_class]} in #{scenario[:controller_action]} (x#{scenario[:occurrences]})"
  end

  open_count   = Issue.open.count
  closed_count = Issue.closed.count
  job_count    = Issue.from_job_failures.count

  puts "\n  Total events created: #{total_events}"
  puts "  Total issues:  #{Issue.count}"
  puts "    Open:        #{open_count}"
  puts "    Closed:      #{closed_count}"
  puts "    Failed jobs: #{job_count}"
end

puts "\n#{'=' * 60}"
puts "  SETUP COMPLETE"
puts "#{'=' * 60}"
puts ""
puts "  Login credentials:"
puts "    Email:    admin@activerabbit.com"
puts "    Password: password123"
puts ""
puts "  Other users: dev@activerabbit.com, qa@activerabbit.com, frontend@activerabbit.com"
puts "  (all use password: password123)"
puts ""
puts "#{'=' * 60}"
