# frozen_string_literal: true

# Seeds SRE analyzer fields onto Issues so the SRE Inbox has realistic
# demo content for every account — creating a Demo App project + demo
# issues for accounts that have none.
#
# Usage:
#   bin/rails runner db/seeds/sre_inbox_demo.rb
#
# Idempotent — safe to re-run.

puts "[sre_inbox_demo] seeding..."

# Canonical fixture set: a mix of resolved / needs_attention / investigating
# states covering realistic exception classes.
FIXTURES = [
  {
    exception_class: "ReferenceError",
    top_frame: "app/javascript/application.js:12:1",
    controller_action: "application.js#init",
    source: "frontend",
    sample_message: "Turbo is not defined",
    resolution_status: "resolved",
    sre_confidence: 88,
    safe_to_auto_merge: true,
    root_cause: {
      "summary" => "Turbo is used in application.js before the import statement resolves in dev builds.",
      "explanation" => "The Stimulus controllers index references Turbo at module load time, " \
                       "but esbuild emits Turbo after the controllers bundle in dev.",
      "triggered_by" => "config"
    },
    fix_diff: "--- a/app/javascript/application.js\n+++ b/app/javascript/application.js\n@@\n-import \"./controllers\"\n+import \"@hotwired/turbo-rails\" // load Turbo first\n+import \"./controllers\"\n",
    pr_status: "pr_created",
    pr_number: 142
  },
  {
    exception_class: "Errno::ENOENT",
    top_frame: "app/jobs/export_cleanup_job.rb:10",
    controller_action: "ExportCleanupJob#perform",
    source: "backend",
    sample_message: "No such file or directory @ apply2files",
    resolution_status: "resolved",
    sre_confidence: 92,
    safe_to_auto_merge: true,
    root_cause: {
      "summary" => "ExportCleanupJob deletes files that may have already been reaped by the tmp purge cron.",
      "explanation" => "File.delete raises when the target is missing. FileUtils.rm_f is idempotent.",
      "triggered_by" => "race_condition"
    },
    fix_diff: "--- a/app/jobs/export_cleanup_job.rb\n+++ b/app/jobs/export_cleanup_job.rb\n-    File.delete(export.file_path)\n+    FileUtils.rm_f(export.file_path)\n",
    pr_status: "merged",
    pr_number: 139
  },
  {
    exception_class: "TypeError",
    top_frame: "app/javascript/controllers/dashboard_controller.js:23:5",
    controller_action: "dashboard_controller.js#renderChart",
    source: "frontend",
    sample_message: "Cannot read properties of null (reading 'data')",
    resolution_status: "resolved",
    sre_confidence: 84,
    safe_to_auto_merge: false,
    root_cause: {
      "summary" => "renderChart receives null when the dashboard API returns zero data points.",
      "explanation" => "Chart.js throws when passed null. Empty-state render should skip chart creation.",
      "triggered_by" => "data_anomaly"
    },
    fix_diff: "--- a/app/javascript/controllers/dashboard_controller.js\n+++ b/app/javascript/controllers/dashboard_controller.js\n+    if (!data || data.length === 0) return this.showEmptyState()\n",
    pr_status: "pr_created_review_needed",
    pr_number: 141
  },
  {
    exception_class: "NameError",
    top_frame: "app/controllers/users/registrations_controller.rb:18",
    controller_action: "Users::RegistrationsController#create",
    source: "backend",
    sample_message: "undefined method `welcome_email' for UserMailer:Class",
    resolution_status: "resolved",
    sre_confidence: 79,
    safe_to_auto_merge: true,
    root_cause: {
      "summary" => "Stale call to UserMailer.welcome_email after it was renamed in v2.14.0.",
      "explanation" => "The mailer method is now welcome. One call site in the registrations flow was missed during the rename.",
      "triggered_by" => "deploy"
    },
    fix_diff: "-    UserMailer.welcome_email(user).deliver_later\n+    UserMailer.welcome(user).deliver_later\n",
    pr_status: "merged",
    pr_number: 138
  },
  {
    exception_class: "RuntimeError",
    top_frame: "app/controllers/webhooks/stripe_controller.rb:42",
    controller_action: "Webhooks::StripeController#create",
    source: "backend",
    sample_message: "Missing customer field on event payload",
    severity: "critical",
    resolution_status: "needs_attention",
    sre_confidence: 71,
    safe_to_auto_merge: false,
    root_cause: {
      "summary" => "Stripe charge.dispute.* events omit data.object.customer — handler assumes it exists.",
      "explanation" => "Fix is simple, but lives in the billing webhook and should be human-reviewed before deploy.",
      "triggered_by" => "external_dependency"
    },
    human_decision_reason: "Touches billing webhook — requires human approval before deploy."
  },
  {
    exception_class: "ActiveRecord::StatementInvalid",
    top_frame: "app/controllers/projects_controller.rb:55",
    controller_action: "ProjectsController#destroy",
    source: "backend",
    sample_message: "PG::DeadlockDetected: deadlock detected",
    severity: "high",
    resolution_status: "needs_attention",
    sre_confidence: 68,
    safe_to_auto_merge: false,
    root_cause: {
      "summary" => "Cascade delete deadlocks against the events ingest path.",
      "explanation" => "Events table lacks ON DELETE CASCADE and is deleted row-by-row in the same transaction. Requires a migration.",
      "triggered_by" => "race_condition"
    },
    human_decision_reason: "Requires database migration — data-integrity sensitive."
  },
  {
    exception_class: "PG::ConnectionBad",
    top_frame: "app/jobs/daily_report_job.rb:15",
    controller_action: "DailyReportJob#perform",
    source: "backend",
    sample_message: "FATAL: remaining connection slots are reserved",
    severity: "medium",
    resolution_status: "needs_attention",
    sre_confidence: 55,
    safe_to_auto_merge: false,
    root_cause: {
      "summary" => "DailyReportJob leaks a connection pool on every run, exhausting PgBouncer.",
      "explanation" => "Under the new hourly cadence pool churn crosses max_client_conn ~3× per day.",
      "triggered_by" => "config"
    },
    human_decision_reason: "Two plausible root causes — human should confirm pool config before deploying."
  },
  {
    exception_class: "Net::ReadTimeout",
    top_frame: "app/controllers/webhooks_controller.rb:88",
    controller_action: "WebhooksController#create",
    source: "backend",
    sample_message: "Net::ReadTimeout with #<TCPSocket>",
    severity: "high",
    resolution_status: "investigating",
    sre_confidence: 30,
    safe_to_auto_merge: false,
    root_cause: {
      "summary" => "Intermittent timeouts on outgoing webhook POSTs — no consistent pattern.",
      "explanation" => "Roughly 3 per hour. APM trace correlation needed.",
      "triggered_by" => "unknown"
    }
  }
].freeze

def build_fingerprint(fixture)
  Issue.generate_fingerprint(
    fixture[:exception_class],
    fixture[:top_frame],
    fixture[:controller_action]
  )
end

def apply_sre_fields!(issue, fixture)
  attrs = {
    resolution_status: fixture[:resolution_status],
    sre_confidence: fixture[:sre_confidence],
    root_cause: fixture[:root_cause],
    fix_diff: fixture[:fix_diff],
    safe_to_auto_merge: fixture[:safe_to_auto_merge],
    sre_analyzed_at: Time.current - rand(0..8).hours,
    severity: fixture[:severity] || issue.severity,
    sre_analysis: {
      "resolution_status" => fixture[:resolution_status],
      "confidence" => fixture[:sre_confidence],
      "root_cause" => fixture[:root_cause],
      "fix" => {
        "diff" => fixture[:fix_diff],
        "safe_to_auto_merge" => fixture[:safe_to_auto_merge]
      },
      "human_decision_required" => fixture[:resolution_status] == "needs_attention",
      "human_decision_reason" => fixture[:human_decision_reason]
    }
  }

  if fixture[:pr_status]
    attrs[:auto_fix_status] = fixture[:pr_status]
    attrs[:auto_fix_pr_number] = fixture[:pr_number]
    attrs[:auto_fix_pr_url] = "https://github.com/example/example/pull/#{fixture[:pr_number]}"
    attrs[:auto_fix_attempted_at] = Time.current - rand(1..12).hours
    attrs[:auto_fix_merged_at] = Time.current - rand(0..6).hours if fixture[:pr_status] == "merged"
  end

  issue.update_columns(attrs.compact)
end

def ensure_demo_project!(account)
  # Slug is globally unique, so scope demo slug per-account.
  slug = account.projects.exists?(slug: "demo-app") ? "demo-app-#{account.id}" : "demo-app"
  project = Project.find_by(slug: slug)
  return project if project

  Project.create!(
    account_id: account.id,
    name: "Demo App",
    slug: slug,
    environment: "production",
    url: "https://demo.example.com",
    tech_stack: "Ruby on Rails",
    active: true
  )
rescue ActiveRecord::RecordInvalid
  # Fall back to unique slug if a different account already claimed "demo-app"
  unique = "demo-app-#{account.id}"
  Project.find_by(slug: unique) || Project.create!(
    account_id: account.id, name: "Demo App", slug: unique,
    environment: "production", url: "https://demo.example.com",
    tech_stack: "Ruby on Rails", active: true
  )
end

def seed_issue!(project, fixture)
  fingerprint = build_fingerprint(fixture)
  issue = Issue.find_by(project_id: project.id, fingerprint: fingerprint)

  if issue.nil?
    now = Time.current
    issue = Issue.create!(
      account_id: project.account_id,
      project_id: project.id,
      fingerprint: fingerprint,
      exception_class: fixture[:exception_class],
      top_frame: fixture[:top_frame],
      controller_action: fixture[:controller_action],
      sample_message: fixture[:sample_message],
      source: fixture[:source] || "backend",
      count: rand(3..25),
      first_seen_at: now - rand(2..36).hours,
      last_seen_at: now - rand(0..2).hours,
      status: fixture[:resolution_status] == "resolved" ? "closed" : "open",
      severity: fixture[:severity]
    )
  end

  apply_sre_fields!(issue, fixture)
  issue
end

total_updated = 0

ActsAsTenant.without_tenant do
  Account.find_each do |account|
    projects = account.projects.to_a

    if projects.empty?
      begin
        projects << ensure_demo_project!(account)
      rescue ActiveRecord::RecordInvalid => e
        puts "  — Acct##{account.id} skipped (could not create demo project: #{e.message})"
        next
      end
    end

    ActsAsTenant.with_tenant(account) do
      projects.each do |project|
        seeded = 0
        FIXTURES.each do |fixture|
          begin
            seed_issue!(project, fixture)
            seeded += 1
            total_updated += 1
          rescue ActiveRecord::RecordInvalid => e
            puts "    ! proj=#{project.slug} fixture=#{fixture[:exception_class]}: #{e.message}"
          end
        end
        puts "  ✓ Acct##{account.id} proj=#{project.slug.ljust(20)} seeded #{seeded}/#{FIXTURES.size} issues"
      end
    end
  end
end

puts "[sre_inbox_demo] done: #{total_updated} issues seeded across #{Account.count} accounts."
