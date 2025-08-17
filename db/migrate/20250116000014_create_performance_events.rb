class CreatePerformanceEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :performance_events do |t|
      t.references :project, null: false, foreign_key: true
      t.references :release, null: true, foreign_key: true
      t.string :target, null: false  # controller#action or job class
      t.float :duration_ms, null: false
      t.float :db_duration_ms
      t.float :view_duration_ms
      t.integer :allocations
      t.integer :sql_queries_count
      t.datetime :occurred_at, null: false
      t.string :environment, null: false, default: 'production'
      t.string :release_version
      t.string :request_path
      t.string :request_method
      t.string :user_id_hash
      t.json :context, default: {}
      t.string :server_name
      t.string :request_id

      t.timestamps
    end

    add_index :performance_events, :target
    add_index :performance_events, :occurred_at
    add_index :performance_events, :duration_ms
    add_index :performance_events, :environment
    add_index :performance_events, [:project_id, :occurred_at]
    add_index :performance_events, [:project_id, :target, :occurred_at]
    add_index :performance_events, :request_id
  end
end
