class CreatePerfRollups < ActiveRecord::Migration[8.0]
  def change
    create_table :perf_rollups do |t|
      t.references :project, null: false, foreign_key: true
      t.string :timeframe, null: false
      t.datetime :timestamp, null: false
      t.string :controller_action, null: false
      t.string :environment, null: false, default: 'production'
      t.integer :request_count, null: false, default: 0
      t.float :avg_duration_ms, null: false, default: 0.0
      t.float :p50_duration_ms, null: false, default: 0.0
      t.float :p95_duration_ms, null: false, default: 0.0
      t.float :p99_duration_ms, null: false, default: 0.0
      t.float :min_duration_ms, null: false, default: 0.0
      t.float :max_duration_ms, null: false, default: 0.0
      t.integer :error_count, null: false, default: 0
      t.integer :n_plus_one_count, null: false, default: 0

      t.timestamps
    end

    add_index :perf_rollups, [:project_id, :timeframe, :timestamp]
    add_index :perf_rollups, [:project_id, :controller_action, :timestamp]
    add_index :perf_rollups, :timestamp
    add_index :perf_rollups, :timeframe
    add_index :perf_rollups, [:project_id, :timeframe, :timestamp, :controller_action, :environment],
              name: 'index_perf_rollups_unique', unique: true
  end
end
