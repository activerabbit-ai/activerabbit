class UpdatePerfRollupsForHdrHistogram < ActiveRecord::Migration[8.0]
  def change
    # Remove indexes that reference controller_action before renaming
    remove_index :perf_rollups, name: 'index_perf_rollups_unique'
    remove_index :perf_rollups, [:project_id, :controller_action, :timestamp]

    # Rename controller_action to target for consistency
    rename_column :perf_rollups, :controller_action, :target

    # Remove n_plus_one_count (this belongs to SQL analysis, not performance rollups)
    remove_column :perf_rollups, :n_plus_one_count, :integer

    # Add HDR histogram blob storage
    add_column :perf_rollups, :hdr_histogram, :binary

    # Recreate indexes with new column name
    add_index :perf_rollups, [:project_id, :timeframe, :timestamp, :target, :environment],
              name: 'index_perf_rollups_unique', unique: true
    add_index :perf_rollups, [:project_id, :target, :timestamp]
  end
end
