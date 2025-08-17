class CreateIssues < ActiveRecord::Migration[8.0]
  def change
    create_table :issues do |t|
      t.references :project, null: false, foreign_key: true
      t.string :fingerprint, null: false
      t.string :exception_type, null: false
      t.text :message, null: false
      t.string :controller_action
      t.string :request_path
      t.string :status, null: false, default: 'open'
      t.integer :count, null: false, default: 0
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :resolved_at
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index :issues, [:project_id, :fingerprint], unique: true
    add_index :issues, :status
    add_index :issues, :last_seen_at
    add_index :issues, :exception_type
  end
end
