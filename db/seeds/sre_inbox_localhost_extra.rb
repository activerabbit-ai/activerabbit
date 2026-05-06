# frozen_string_literal: true

# Seeds 20 extra issues onto the "localhost" project for the admin@activerabbit.com
# account, so the SRE Inbox at /inbox shows the full bucket flow.
#
# Usage:
#   bin/rails runner db/seeds/sre_inbox_localhost_extra.rb
#
# Idempotent: each fixture has a stable fingerprint key — re-running upserts.

USER_EMAIL    = "admin@activerabbit.com"
PROJECT_SLUG  = "localhost"

user    = User.find_by(email: USER_EMAIL) or abort("[seed] no user #{USER_EMAIL}")
account = user.account                    or abort("[seed] no account for #{USER_EMAIL}")
project = ActsAsTenant.without_tenant { account.projects.find_by(slug: PROJECT_SLUG) } \
            or abort("[seed] no project '#{PROJECT_SLUG}' in account '#{account.name}'")

puts "[seed] account=#{account.id} project=#{project.id} (#{project.name}) — adding 20 issues"

# ── 20 issues spread across the inbox buckets ───────────────────────
# Bucket distribution:
#   needs_review : 6   (3× needs_attention, 1× pr_created_review_needed,
#                       1× ci_failed, 1× merge_failed)
#   agent_working: 5   (2× investigating, 1× creating_pr, 1× pr_created,
#                       1× ci_pending)
#   shipped      : 6   (4× merged PR, 2× resolved with no PR)
#   only "all"   : 3   (raw — no resolution_status, no PR)

FIXTURES = [
  # ── Needs review (human required) ─────────────────────────────────
  { key: "lh-1", exception_class: "ActiveRecord::RecordNotUnique",
    top_frame: "app/controllers/users_controller.rb:64",
    controller_action: "UsersController#create", source: "backend",
    sample_message: "duplicate key value violates unique constraint \"users_email_idx\"",
    severity: "high",
    resolution_status: "needs_attention",
    sre_confidence: 72,
    safe_to_auto_merge: false,
    root_cause: { "summary" => "Email uniqueness check happens after the INSERT.",
                  "explanation" => "Validation is missing — relying on the DB raises late.",
                  "triggered_by" => "race_condition" } },

  { key: "lh-2", exception_class: "Stripe::CardError",
    top_frame: "app/services/billing/charge_service.rb:23",
    controller_action: "Billing::ChargeService#call", source: "backend",
    sample_message: "Your card was declined.",
    severity: "critical",
    resolution_status: "needs_attention",
    sre_confidence: 65,
    safe_to_auto_merge: false,
    root_cause: { "summary" => "Card error surfaced as 500 instead of being handled.",
                  "explanation" => "Touches billing — needs human review.",
                  "triggered_by" => "external_dependency" } },

  { key: "lh-3", exception_class: "ActionController::ParameterMissing",
    top_frame: "app/controllers/api/v1/webhooks_controller.rb:18",
    controller_action: "Api::V1::WebhooksController#github", source: "backend",
    sample_message: "param is missing or the value is empty: payload",
    severity: "medium",
    resolution_status: "needs_attention",
    sre_confidence: 58,
    safe_to_auto_merge: false,
    root_cause: { "summary" => "GitHub redelivers webhooks without payload after retries.",
                  "explanation" => "Need to whitelist replays before strict_params kicks in.",
                  "triggered_by" => "external_dependency" } },

  { key: "lh-4", exception_class: "ArgumentError",
    top_frame: "app/services/exporter.rb:88",
    controller_action: "ExportsController#create", source: "backend",
    sample_message: "wrong number of arguments (given 2, expected 1)",
    severity: "high",
    resolution_status: nil,
    sre_confidence: 81,
    safe_to_auto_merge: false,
    root_cause: { "summary" => "Exporter signature changed in v3 — caller still passes legacy args.",
                  "explanation" => "PR is open but reviewer has flagged it.",
                  "triggered_by" => "deploy" },
    fix_diff: "-    Exporter.new(user, opts)\n+    Exporter.new(user)\n",
    pr_status: "pr_created_review_needed", pr_number: 201 },

  { key: "lh-5", exception_class: "Net::OpenTimeout",
    top_frame: "app/jobs/sync_calendar_job.rb:42",
    controller_action: "SyncCalendarJob#perform", source: "backend",
    sample_message: "execution expired",
    severity: "high",
    resolution_status: nil,
    sre_confidence: 70,
    safe_to_auto_merge: true,
    root_cause: { "summary" => "Calendar API has been flaky for 3 days; agent's retry-fix CI failed.",
                  "explanation" => "CI exposed a regression in another worker — needs human triage.",
                  "triggered_by" => "external_dependency" },
    fix_diff: "+      retry_on Net::OpenTimeout, attempts: 3, wait: :exponentially_longer\n",
    pr_status: "ci_failed", pr_number: 202 },

  { key: "lh-6", exception_class: "PG::ForeignKeyViolation",
    top_frame: "app/models/order.rb:140",
    controller_action: "OrdersController#destroy", source: "backend",
    sample_message: "violates foreign key constraint \"order_items_order_id_fkey\"",
    severity: "critical",
    resolution_status: nil,
    sre_confidence: 60,
    safe_to_auto_merge: false,
    root_cause: { "summary" => "Orders are deleted before children — needs migration to add cascade.",
                  "explanation" => "Auto-merge attempt got rejected by main branch protection.",
                  "triggered_by" => "race_condition" },
    fix_diff: "+    has_many :order_items, dependent: :destroy\n",
    pr_status: "merge_failed", pr_number: 203 },

  # ── Agent working (in flight) ─────────────────────────────────────
  { key: "lh-7", exception_class: "Net::ReadTimeout",
    top_frame: "app/services/openai_client.rb:55",
    controller_action: "OpenaiClient#complete", source: "backend",
    sample_message: "Net::ReadTimeout with #<TCPSocket>",
    severity: "medium",
    resolution_status: "investigating",
    sre_confidence: 35,
    safe_to_auto_merge: false,
    root_cause: { "summary" => "Latency spikes on OpenAI completions endpoint.",
                  "explanation" => "Agent is correlating with their status page.",
                  "triggered_by" => "unknown" } },

  { key: "lh-8", exception_class: "Encoding::UndefinedConversionError",
    top_frame: "app/services/csv_importer.rb:22",
    controller_action: "ImportsController#create", source: "backend",
    sample_message: "\"\\xC3\" from ASCII-8BIT to UTF-8",
    severity: "medium",
    resolution_status: "investigating",
    sre_confidence: 42,
    safe_to_auto_merge: false,
    root_cause: { "summary" => "Customer uploaded a Latin-1 CSV; importer assumes UTF-8.",
                  "explanation" => "Need to detect encoding before parsing.",
                  "triggered_by" => "data_anomaly" } },

  { key: "lh-9", exception_class: "NoMethodError",
    top_frame: "app/controllers/dashboard_controller.rb:31",
    controller_action: "DashboardController#index", source: "backend",
    sample_message: "undefined method `display_name' for nil:NilClass",
    severity: "medium",
    resolution_status: nil,
    sre_confidence: 86,
    safe_to_auto_merge: true,
    root_cause: { "summary" => "Some users have no associated organization yet.",
                  "explanation" => "Use safe navigation in the dashboard greeting.",
                  "triggered_by" => "config" },
    fix_diff: "-    @greeting = \"Welcome, \#{current_user.organization.display_name}\"\n+    @greeting = \"Welcome, \#{current_user.organization&.display_name}\"\n",
    pr_status: "creating_pr", pr_number: 204 },

  { key: "lh-10", exception_class: "TypeError",
    top_frame: "app/javascript/controllers/upload_controller.js:88:7",
    controller_action: "upload_controller.js#chunk", source: "frontend",
    sample_message: "Cannot read properties of undefined (reading 'size')",
    severity: "high",
    resolution_status: nil,
    sre_confidence: 78,
    safe_to_auto_merge: true,
    root_cause: { "summary" => "Empty FileList passed to chunker when user clicks Upload twice.",
                  "explanation" => "Guard the chunker to no-op on empty input.",
                  "triggered_by" => "data_anomaly" },
    fix_diff: "+    if (!files || files.length === 0) return\n",
    pr_status: "pr_created", pr_number: 205 },

  { key: "lh-11", exception_class: "ActiveRecord::Deadlocked",
    top_frame: "app/models/inventory.rb:55",
    controller_action: "InventoryController#decrement", source: "backend",
    sample_message: "PG::TRDeadlockDetected: deadlock detected",
    severity: "high",
    resolution_status: nil,
    sre_confidence: 73,
    safe_to_auto_merge: true,
    root_cause: { "summary" => "Concurrent stock decrements lock rows in inconsistent order.",
                  "explanation" => "Sort sku_ids before locking.",
                  "triggered_by" => "race_condition" },
    fix_diff: "-    skus.each { |s| s.lock! }\n+    skus.sort_by(&:id).each { |s| s.lock! }\n",
    pr_status: "ci_pending", pr_number: 206 },

  # ── Shipped (terminal) ────────────────────────────────────────────
  { key: "lh-12", exception_class: "RuntimeError",
    top_frame: "app/services/feature_flag_resolver.rb:31",
    controller_action: "FeatureFlagResolver#resolve", source: "backend",
    sample_message: "unknown feature: experimental_search_v2",
    severity: "low",
    resolution_status: "resolved",
    sre_confidence: 92,
    safe_to_auto_merge: true,
    root_cause: { "summary" => "Stale flag reference left after experiment was rolled out.",
                  "explanation" => "Removed the gate.",
                  "triggered_by" => "deploy" },
    fix_diff: "-    return unless FeatureFlag.on?(:experimental_search_v2)\n",
    pr_status: "merged", pr_number: 191 },

  { key: "lh-13", exception_class: "NoMethodError",
    top_frame: "app/javascript/controllers/timer_controller.js:19:8",
    controller_action: "timer_controller.js#tick", source: "frontend",
    sample_message: "this.timeoutValue is not a function",
    severity: "low",
    resolution_status: "resolved",
    sre_confidence: 95,
    safe_to_auto_merge: true,
    root_cause: { "summary" => "Stimulus value reader name collided with the method.",
                  "explanation" => "Renamed to delayMs.",
                  "triggered_by" => "config" },
    fix_diff: "-    static values = { timeout: Number }\n+    static values = { delayMs: Number }\n",
    pr_status: "merged", pr_number: 188 },

  { key: "lh-14", exception_class: "JSON::ParserError",
    top_frame: "app/services/slack_notifier.rb:42",
    controller_action: "SlackNotifier#post", source: "backend",
    sample_message: "unexpected token at '<html>'",
    severity: "medium",
    resolution_status: "resolved",
    sre_confidence: 88,
    safe_to_auto_merge: true,
    root_cause: { "summary" => "Slack returned HTML maintenance page; parser exploded.",
                  "explanation" => "Check content-type before parsing.",
                  "triggered_by" => "external_dependency" },
    fix_diff: "+    return unless res[\"content-type\"]&.include?(\"json\")\n",
    pr_status: "merged", pr_number: 184 },

  { key: "lh-15", exception_class: "ActionController::RoutingError",
    top_frame: "lib/middleware/redirect_legacy.rb:14",
    controller_action: "Rack#call", source: "backend",
    sample_message: "No route matches [GET] \"/v1/old-endpoint\"",
    severity: "low",
    resolution_status: "resolved",
    sre_confidence: 90,
    safe_to_auto_merge: true,
    root_cause: { "summary" => "Old SDK still hitting /v1/old-endpoint.",
                  "explanation" => "Added a 308 redirect to the new path.",
                  "triggered_by" => "deploy" },
    fix_diff: "+      get \"/v1/old-endpoint\", to: redirect(\"/api/v2/legacy\", status: 308)\n",
    pr_status: "merged", pr_number: 180 },

  { key: "lh-16", exception_class: "Faraday::ConnectionFailed",
    top_frame: "app/services/intercom_sync.rb:11",
    controller_action: "IntercomSync#perform", source: "backend",
    sample_message: "Failed to open TCP connection to api.intercom.io:443",
    severity: "low",
    resolution_status: "resolved",
    sre_confidence: 0,
    safe_to_auto_merge: false,
    root_cause: nil },

  { key: "lh-17", exception_class: "Errno::EACCES",
    top_frame: "app/jobs/file_cleanup_job.rb:8",
    controller_action: "FileCleanupJob#perform", source: "backend",
    sample_message: "Permission denied @ rb_sysopen - /tmp/legacy.lock",
    severity: "low",
    resolution_status: "resolved",
    sre_confidence: 0,
    safe_to_auto_merge: false,
    root_cause: nil },

  # ── Only in "All errors" (raw, un-analyzed) ──────────────────────
  { key: "lh-18", exception_class: "NameError",
    top_frame: "app/services/onboarding/welcome_step.rb:12",
    controller_action: "Onboarding::WelcomeStep#run", source: "backend",
    sample_message: "uninitialized constant Onboarding::WelcomeStep::Mailer",
    severity: "medium",
    resolution_status: nil,
    sre_confidence: nil,
    safe_to_auto_merge: nil },

  { key: "lh-19", exception_class: "ActionView::MissingTemplate",
    top_frame: "app/controllers/reports_controller.rb:22",
    controller_action: "ReportsController#weekly", source: "backend",
    sample_message: "Missing template reports/weekly with {locale: [:en]}",
    severity: "low",
    resolution_status: nil,
    sre_confidence: nil,
    safe_to_auto_merge: nil },

  { key: "lh-20", exception_class: "TypeError",
    top_frame: "app/javascript/controllers/search_controller.js:12:5",
    controller_action: "search_controller.js#submit", source: "frontend",
    sample_message: "this.element.querySelectorAll(...).forEach is not a function",
    severity: "medium",
    resolution_status: nil,
    sre_confidence: nil,
    safe_to_auto_merge: nil }
].freeze

def fingerprint_for(fixture, project)
  Issue.generate_fingerprint(
    fixture[:exception_class],
    fixture[:top_frame],
    fixture[:controller_action]
  )
end

def upsert_issue!(project, fixture)
  fp  = fingerprint_for(fixture, project)
  now = Time.current
  first_seen = now - rand(1..28).days - rand(0..23).hours

  issue = Issue.find_by(project_id: project.id, fingerprint: fp)
  issue ||= Issue.create!(
    account_id:        project.account_id,
    project_id:        project.id,
    fingerprint:       fp,
    exception_class:   fixture[:exception_class],
    top_frame:         fixture[:top_frame],
    controller_action: fixture[:controller_action],
    sample_message:    fixture[:sample_message],
    source:            fixture[:source] || "backend",
    severity:          fixture[:severity],
    count:             rand(2..50),
    first_seen_at:     first_seen,
    last_seen_at:      now - rand(0..6).hours,
    status:            fixture[:resolution_status] == "resolved" ? "closed" : "open"
  )

  attrs = {
    resolution_status:  fixture[:resolution_status],
    sre_confidence:     fixture[:sre_confidence],
    root_cause:         fixture[:root_cause],
    fix_diff:           fixture[:fix_diff],
    safe_to_auto_merge: fixture[:safe_to_auto_merge],
    sre_analyzed_at:    fixture[:sre_confidence] ? now - rand(0..3).days : nil,
    severity:           fixture[:severity] || issue.severity,
    sre_analysis: fixture[:sre_confidence] && {
      "resolution_status"        => fixture[:resolution_status],
      "confidence"               => fixture[:sre_confidence],
      "root_cause"               => fixture[:root_cause],
      "fix" => { "diff" => fixture[:fix_diff], "safe_to_auto_merge" => fixture[:safe_to_auto_merge] },
      "human_decision_required"  => fixture[:resolution_status] == "needs_attention",
      "human_decision_reason"    => fixture[:human_decision_reason]
    } || nil
  }

  if fixture[:pr_status]
    attrs[:auto_fix_status]       = fixture[:pr_status]
    attrs[:auto_fix_pr_number]    = fixture[:pr_number]
    attrs[:auto_fix_pr_url]       = "https://github.com/example/example/pull/#{fixture[:pr_number]}"
    attrs[:auto_fix_attempted_at] = now - rand(1..72).hours
    attrs[:auto_fix_merged_at]    = (now - rand(0..48).hours) if fixture[:pr_status] == "merged"
  end

  issue.update_columns(attrs.compact)
  issue
end

ActsAsTenant.with_tenant(account) do
  FIXTURES.each do |fixture|
    issue = upsert_issue!(project, fixture)
    print "."
  end
  puts
end

base = Issue.where(project_id: project.id)
shipped = base.where(auto_fix_status: %w[merged]).count + base.where(resolution_status: "resolved", auto_fix_status: nil).count
needs   = base.where("resolution_status = ? OR auto_fix_status IN (?)",
                    "needs_attention", %w[pr_created_review_needed ci_failed ci_timeout merge_failed failed monitor_error]).count
working = base.where("(resolution_status = ? AND auto_fix_status IS NULL) OR auto_fix_status IN (?)",
                    "investigating", %w[creating_pr pr_created ci_pending ci_passed]).count

puts "[seed] done. project '#{project.slug}' totals → all=#{base.count} needs_review~#{needs} agent_working~#{working} shipped~#{shipped}"
