class AddCachedUsageToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :cached_events_used, :integer, default: 0, null: false
    add_column :accounts, :cached_ai_summaries_used, :integer, default: 0, null: false
    add_column :accounts, :cached_pull_requests_used, :integer, default: 0, null: false
    add_column :accounts, :cached_uptime_monitors_used, :integer, default: 0, null: false
    add_column :accounts, :cached_status_pages_used, :integer, default: 0, null: false
    add_column :accounts, :cached_projects_used, :integer, default: 0, null: false
    add_column :accounts, :usage_cached_at, :datetime
  end
end
