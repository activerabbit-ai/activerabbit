class AddCachedPerformanceEventsToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :cached_performance_events_used, :integer, default: 0, null: false
  end
end
