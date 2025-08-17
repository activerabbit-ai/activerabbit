class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.references :project, null: false, foreign_key: true
      t.references :issue, null: true, foreign_key: true
      t.bigint :release_id, null: true  # Will add foreign key later
      t.string :event_type, null: false
      t.string :fingerprint, null: false
      t.json :payload, null: false
      t.datetime :occurred_at, null: false
      t.string :environment, null: false, default: 'production'
      t.string :release_version
      t.string :user_id_hash
      t.float :duration_ms
      t.string :controller_action
      t.string :request_path
      t.integer :sql_queries_count
      t.boolean :n_plus_one_detected, default: false

      t.timestamps
    end

    add_index :events, :event_type
    add_index :events, :occurred_at
    add_index :events, :fingerprint
    add_index :events, :environment
    add_index :events, :release_version
    add_index :events, :release_id
    add_index :events, [:project_id, :occurred_at]
    add_index :events, [:project_id, :event_type, :occurred_at]
  end
end
