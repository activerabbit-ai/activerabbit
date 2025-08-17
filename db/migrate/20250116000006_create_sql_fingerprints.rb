class CreateSqlFingerprints < ActiveRecord::Migration[8.0]
  def change
    create_table :sql_fingerprints do |t|
      t.references :project, null: false, foreign_key: true
      t.string :fingerprint, null: false
      t.string :query_type, null: false
      t.text :normalized_query, null: false
      t.string :controller_action
      t.integer :total_count, null: false, default: 0
      t.float :total_duration_ms, null: false, default: 0.0
      t.float :avg_duration_ms, null: false, default: 0.0
      t.float :max_duration_ms, null: false, default: 0.0
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false

      t.timestamps
    end

    add_index :sql_fingerprints, [:project_id, :fingerprint], unique: true
    add_index :sql_fingerprints, :query_type
    add_index :sql_fingerprints, :total_count
    add_index :sql_fingerprints, :avg_duration_ms
    add_index :sql_fingerprints, :last_seen_at
  end
end
