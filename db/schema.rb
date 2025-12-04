# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_12_04_185528) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.string "name", null: false
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "settings", default: {}
    t.string "current_plan", default: "developer", null: false
    t.string "billing_interval", default: "month", null: false
    t.boolean "ai_mode_enabled", default: false, null: false
    t.datetime "trial_ends_at"
    t.datetime "event_usage_period_start"
    t.datetime "event_usage_period_end"
    t.integer "event_quota", default: 50000, null: false
    t.integer "events_used_in_period", default: 0, null: false
    t.string "overage_subscription_item_id"
    t.string "ai_overage_subscription_item_id"
    t.jsonb "last_quota_alert_sent_at"
    t.index ["name"], name: "index_accounts_on_name"
  end

  create_table "ai_requests", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "user_id", null: false
    t.string "subscription_id"
    t.string "request_type"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "occurred_at"], name: "index_ai_requests_on_account_id_and_occurred_at"
    t.index ["user_id"], name: "index_ai_requests_on_user_id"
  end

  create_table "alert_notifications", force: :cascade do |t|
    t.bigint "alert_rule_id", null: false
    t.bigint "project_id", null: false
    t.string "notification_type", null: false
    t.string "status", default: "pending", null: false
    t.json "payload", null: false
    t.datetime "sent_at"
    t.datetime "failed_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id", null: false
    t.index ["account_id", "alert_rule_id"], name: "index_alert_notifications_on_account_id_and_alert_rule_id"
    t.index ["account_id"], name: "index_alert_notifications_on_account_id"
    t.index ["alert_rule_id"], name: "index_alert_notifications_on_alert_rule_id"
    t.index ["created_at"], name: "index_alert_notifications_on_created_at"
    t.index ["notification_type"], name: "index_alert_notifications_on_notification_type"
    t.index ["project_id"], name: "index_alert_notifications_on_project_id"
    t.index ["status"], name: "index_alert_notifications_on_status"
  end

  create_table "alert_rules", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "name", null: false
    t.string "rule_type", null: false
    t.float "threshold_value", null: false
    t.integer "time_window_minutes", default: 60, null: false
    t.integer "cooldown_minutes", default: 60, null: false
    t.boolean "enabled", default: true, null: false
    t.json "conditions", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id", null: false
    t.index ["account_id", "project_id"], name: "index_alert_rules_on_account_id_and_project_id"
    t.index ["account_id"], name: "index_alert_rules_on_account_id"
    t.index ["enabled"], name: "index_alert_rules_on_enabled"
    t.index ["project_id", "rule_type"], name: "index_alert_rules_on_project_id_and_rule_type"
    t.index ["project_id"], name: "index_alert_rules_on_project_id"
  end

  create_table "api_tokens", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "name", null: false
    t.string "token", null: false
    t.boolean "active", default: true, null: false
    t.integer "usage_count", default: 0, null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id", null: false
    t.index ["account_id"], name: "index_api_tokens_on_account_id"
    t.index ["active"], name: "index_api_tokens_on_active"
    t.index ["project_id", "active"], name: "index_api_tokens_on_project_id_and_active"
    t.index ["project_id"], name: "index_api_tokens_on_project_id"
    t.index ["token"], name: "index_api_tokens_on_token", unique: true
  end

  create_table "daily_event_counts", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "day", null: false
    t.integer "count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "day"], name: "index_daily_event_counts_on_account_id_and_day", unique: true
    t.index ["account_id"], name: "index_daily_event_counts_on_account_id"
  end

  create_table "daily_resource_usages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.date "day", null: false
    t.integer "errors_count"
    t.integer "ai_summaries_count"
    t.integer "pull_requests_count"
    t.integer "uptime_monitors_count"
    t.integer "status_pages_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "day"], name: "index_daily_resource_usages_on_account_id_and_day", unique: true
  end

  create_table "deploys", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "release_id", null: false
    t.bigint "user_id"
    t.bigint "account_id", null: false
    t.string "status"
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.jsonb "metadata"
    t.jsonb "errors_metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_deploys_on_account_id"
    t.index ["project_id"], name: "index_deploys_on_project_id"
    t.index ["release_id"], name: "index_deploys_on_release_id"
    t.index ["user_id"], name: "index_deploys_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "issue_id"
    t.bigint "release_id"
    t.datetime "occurred_at", null: false
    t.string "environment", default: "production", null: false
    t.string "release_version"
    t.string "user_id_hash"
    t.string "controller_action"
    t.string "request_path"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "exception_class", null: false
    t.text "message", null: false
    t.text "backtrace"
    t.string "request_method"
    t.json "context", default: {}
    t.string "server_name"
    t.string "request_id"
    t.bigint "account_id", null: false
    t.bigint "deploy_id"
    t.index ["account_id", "project_id"], name: "index_events_on_account_id_and_project_id"
    t.index ["account_id"], name: "index_events_on_account_id"
    t.index ["deploy_id"], name: "index_events_on_deploy_id"
    t.index ["environment"], name: "index_events_on_environment"
    t.index ["exception_class"], name: "index_events_on_exception_class"
    t.index ["issue_id"], name: "index_events_on_issue_id"
    t.index ["occurred_at"], name: "index_events_on_occurred_at"
    t.index ["project_id", "occurred_at"], name: "index_events_on_project_id_and_occurred_at"
    t.index ["project_id"], name: "index_events_on_project_id"
    t.index ["release_id"], name: "index_events_on_release_id"
    t.index ["release_version"], name: "index_events_on_release_version"
    t.index ["request_id"], name: "index_events_on_request_id"
    t.index ["server_name"], name: "index_events_on_server_name"
  end

  create_table "healthchecks", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "name", null: false
    t.string "check_type", null: false
    t.json "config", default: {}
    t.boolean "enabled", default: true, null: false
    t.string "status", default: "unknown", null: false
    t.datetime "last_checked_at"
    t.float "response_time_ms"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id", null: false
    t.index ["account_id", "project_id"], name: "index_healthchecks_on_account_id_and_project_id"
    t.index ["account_id"], name: "index_healthchecks_on_account_id"
    t.index ["check_type"], name: "index_healthchecks_on_check_type"
    t.index ["enabled"], name: "index_healthchecks_on_enabled"
    t.index ["last_checked_at"], name: "index_healthchecks_on_last_checked_at"
    t.index ["project_id", "name"], name: "index_healthchecks_on_project_id_and_name", unique: true
    t.index ["project_id"], name: "index_healthchecks_on_project_id"
    t.index ["status"], name: "index_healthchecks_on_status"
  end

  create_table "issues", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "fingerprint", null: false
    t.string "controller_action"
    t.string "status", default: "open", null: false
    t.integer "count", default: 0, null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "exception_class", null: false
    t.text "top_frame", null: false
    t.text "sample_message"
    t.datetime "closed_at"
    t.bigint "account_id", null: false
    t.text "ai_summary"
    t.datetime "ai_summary_generated_at"
    t.index ["account_id"], name: "index_issues_on_account_id"
    t.index ["closed_at"], name: "index_issues_on_closed_at"
    t.index ["exception_class"], name: "index_issues_on_exception_class"
    t.index ["last_seen_at"], name: "index_issues_on_last_seen_at"
    t.index ["project_id", "fingerprint"], name: "index_issues_on_project_id_and_fingerprint", unique: true
    t.index ["project_id"], name: "index_issues_on_project_id"
    t.index ["status"], name: "index_issues_on_status"
  end

  create_table "pay_charges", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "processor_id", null: false
    t.integer "amount", null: false
    t.string "currency"
    t.integer "application_fee_amount"
    t.integer "amount_refunded"
    t.json "metadata"
    t.json "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_pay_charges_on_customer_id"
    t.index ["processor_id"], name: "index_pay_charges_on_processor_id", unique: true
  end

  create_table "pay_customers", force: :cascade do |t|
    t.string "processor", null: false
    t.string "processor_id"
    t.boolean "default"
    t.json "data"
    t.string "owner_type"
    t.bigint "owner_id"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "type"
    t.index ["owner_type", "owner_id", "deleted_at"], name: "customer_owner_processor_index"
    t.index ["processor", "processor_id"], name: "index_pay_customers_on_processor_and_processor_id"
    t.index ["type"], name: "index_pay_customers_on_type"
  end

  create_table "pay_payment_methods", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "processor_id", null: false
    t.boolean "default"
    t.string "type"
    t.json "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_pay_payment_methods_on_customer_id"
    t.index ["processor_id"], name: "index_pay_payment_methods_on_processor_id", unique: true
  end

  create_table "pay_subscriptions", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "name", null: false
    t.string "processor_id", null: false
    t.string "processor_plan", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", null: false
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.datetime "trial_ends_at"
    t.datetime "ends_at"
    t.decimal "application_fee_percent", precision: 8, scale: 4
    t.json "metadata"
    t.json "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_subscriptions_on_customer_id_and_processor_id", unique: true
    t.index ["customer_id"], name: "index_pay_subscriptions_on_customer_id"
    t.index ["processor_id"], name: "index_pay_subscriptions_on_processor_id", unique: true
  end

  create_table "pay_webhooks", force: :cascade do |t|
    t.string "processor"
    t.string "event_type"
    t.json "event"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "perf_rollups", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "timeframe", null: false
    t.datetime "timestamp", null: false
    t.string "target", null: false
    t.string "environment", default: "production", null: false
    t.integer "request_count", default: 0, null: false
    t.float "avg_duration_ms", default: 0.0, null: false
    t.float "p50_duration_ms", default: 0.0, null: false
    t.float "p95_duration_ms", default: 0.0, null: false
    t.float "p99_duration_ms", default: 0.0, null: false
    t.float "min_duration_ms", default: 0.0, null: false
    t.float "max_duration_ms", default: 0.0, null: false
    t.integer "error_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.binary "hdr_histogram"
    t.bigint "account_id", null: false
    t.index ["account_id", "project_id"], name: "index_perf_rollups_on_account_id_and_project_id"
    t.index ["account_id"], name: "index_perf_rollups_on_account_id"
    t.index ["project_id", "target", "timestamp"], name: "index_perf_rollups_on_project_id_and_target_and_timestamp"
    t.index ["project_id", "timeframe", "timestamp", "target", "environment"], name: "index_perf_rollups_unique", unique: true
    t.index ["project_id", "timeframe", "timestamp"], name: "index_perf_rollups_on_project_id_and_timeframe_and_timestamp"
    t.index ["project_id"], name: "index_perf_rollups_on_project_id"
    t.index ["timeframe"], name: "index_perf_rollups_on_timeframe"
    t.index ["timestamp"], name: "index_perf_rollups_on_timestamp"
  end

  create_table "performance_events", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.bigint "release_id"
    t.string "target", null: false
    t.float "duration_ms", null: false
    t.float "db_duration_ms"
    t.float "view_duration_ms"
    t.integer "allocations"
    t.integer "sql_queries_count"
    t.datetime "occurred_at", null: false
    t.string "environment", default: "production", null: false
    t.string "release_version"
    t.string "request_path"
    t.string "request_method"
    t.string "user_id_hash"
    t.json "context", default: {}
    t.string "server_name"
    t.string "request_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id", null: false
    t.index ["account_id", "project_id"], name: "index_performance_events_on_account_id_and_project_id"
    t.index ["account_id"], name: "index_performance_events_on_account_id"
    t.index ["duration_ms"], name: "index_performance_events_on_duration_ms"
    t.index ["environment"], name: "index_performance_events_on_environment"
    t.index ["occurred_at"], name: "index_performance_events_on_occurred_at"
    t.index ["project_id", "occurred_at"], name: "index_performance_events_on_project_id_and_occurred_at"
    t.index ["project_id", "target", "occurred_at"], name: "idx_on_project_id_target_occurred_at_2f7b1bed68"
    t.index ["project_id"], name: "index_performance_events_on_project_id"
    t.index ["release_id"], name: "index_performance_events_on_release_id"
    t.index ["request_id"], name: "index_performance_events_on_request_id"
    t.index ["target"], name: "index_performance_events_on_target"
  end

  create_table "performance_summaries", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "project_id", null: false
    t.string "target", null: false
    t.text "summary"
    t.datetime "generated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_performance_summaries_on_account_id"
    t.index ["project_id", "target"], name: "index_performance_summaries_on_project_id_and_target", unique: true
    t.index ["project_id"], name: "index_performance_summaries_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "environment", default: "production", null: false
    t.text "description"
    t.boolean "active", default: true, null: false
    t.json "settings", default: {}
    t.string "health_status", default: "unknown"
    t.datetime "last_event_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id", null: false
    t.string "url"
    t.string "tech_stack"
    t.string "slack_access_token"
    t.string "slack_team_id"
    t.string "slack_team_name"
    t.string "slack_channel_id"
    t.index ["account_id"], name: "index_projects_on_account_id"
    t.index ["active"], name: "index_projects_on_active"
    t.index ["environment"], name: "index_projects_on_environment"
    t.index ["slug"], name: "index_projects_on_slug", unique: true
    t.index ["user_id", "name"], name: "index_projects_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "releases", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "version", null: false
    t.string "environment", default: "production", null: false
    t.datetime "deployed_at", null: false
    t.boolean "regression_detected", default: false
    t.json "regression_data", default: {}
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id", null: false
    t.index ["account_id", "project_id"], name: "index_releases_on_account_id_and_project_id"
    t.index ["account_id"], name: "index_releases_on_account_id"
    t.index ["deployed_at"], name: "index_releases_on_deployed_at"
    t.index ["environment"], name: "index_releases_on_environment"
    t.index ["project_id", "version"], name: "index_releases_on_project_id_and_version", unique: true
    t.index ["project_id"], name: "index_releases_on_project_id"
    t.index ["regression_detected"], name: "index_releases_on_regression_detected"
  end

  create_table "sql_fingerprints", force: :cascade do |t|
    t.bigint "project_id", null: false
    t.string "fingerprint", null: false
    t.string "query_type", null: false
    t.text "normalized_query", null: false
    t.string "controller_action"
    t.integer "total_count", default: 0, null: false
    t.float "total_duration_ms", default: 0.0, null: false
    t.float "avg_duration_ms", default: 0.0, null: false
    t.float "max_duration_ms", default: 0.0, null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "account_id", null: false
    t.index ["account_id", "project_id"], name: "index_sql_fingerprints_on_account_id_and_project_id"
    t.index ["account_id"], name: "index_sql_fingerprints_on_account_id"
    t.index ["avg_duration_ms"], name: "index_sql_fingerprints_on_avg_duration_ms"
    t.index ["last_seen_at"], name: "index_sql_fingerprints_on_last_seen_at"
    t.index ["project_id", "fingerprint"], name: "index_sql_fingerprints_on_project_id_and_fingerprint", unique: true
    t.index ["project_id"], name: "index_sql_fingerprints_on_project_id"
    t.index ["query_type"], name: "index_sql_fingerprints_on_query_type"
    t.index ["total_count"], name: "index_sql_fingerprints_on_total_count"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.bigint "account_id", null: false
    t.string "provider"
    t.string "uid"
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "webhook_events", force: :cascade do |t|
    t.string "provider", null: false
    t.string "event_id", null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "event_id"], name: "idx_webhook_events_unique", unique: true
  end

  add_foreign_key "alert_notifications", "accounts"
  add_foreign_key "alert_notifications", "alert_rules"
  add_foreign_key "alert_notifications", "projects"
  add_foreign_key "alert_rules", "accounts"
  add_foreign_key "alert_rules", "projects"
  add_foreign_key "api_tokens", "accounts"
  add_foreign_key "api_tokens", "projects"
  add_foreign_key "daily_event_counts", "accounts"
  add_foreign_key "daily_resource_usages", "accounts"
  add_foreign_key "deploys", "accounts"
  add_foreign_key "deploys", "projects"
  add_foreign_key "deploys", "releases"
  add_foreign_key "deploys", "users"
  add_foreign_key "events", "accounts"
  add_foreign_key "events", "deploys"
  add_foreign_key "events", "issues"
  add_foreign_key "events", "projects"
  add_foreign_key "events", "releases"
  add_foreign_key "healthchecks", "accounts"
  add_foreign_key "healthchecks", "projects"
  add_foreign_key "issues", "accounts"
  add_foreign_key "issues", "projects"
  add_foreign_key "pay_charges", "pay_customers", column: "customer_id"
  add_foreign_key "pay_payment_methods", "pay_customers", column: "customer_id"
  add_foreign_key "pay_subscriptions", "pay_customers", column: "customer_id"
  add_foreign_key "perf_rollups", "accounts"
  add_foreign_key "perf_rollups", "projects"
  add_foreign_key "performance_events", "accounts"
  add_foreign_key "performance_events", "projects"
  add_foreign_key "performance_events", "releases"
  add_foreign_key "performance_summaries", "accounts"
  add_foreign_key "performance_summaries", "projects"
  add_foreign_key "projects", "accounts"
  add_foreign_key "projects", "users"
  add_foreign_key "releases", "accounts"
  add_foreign_key "releases", "projects"
  add_foreign_key "sql_fingerprints", "accounts"
  add_foreign_key "sql_fingerprints", "projects"
  add_foreign_key "users", "accounts"
end
