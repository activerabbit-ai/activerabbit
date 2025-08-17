class CreateHealthchecks < ActiveRecord::Migration[8.0]
  def change
    create_table :healthchecks do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :check_type, null: false
      t.json :config, default: {}
      t.boolean :enabled, null: false, default: true
      t.string :status, null: false, default: 'unknown'
      t.datetime :last_checked_at
      t.float :response_time_ms
      t.text :message

      t.timestamps
    end

    add_index :healthchecks, [:project_id, :name], unique: true
    add_index :healthchecks, :check_type
    add_index :healthchecks, :status
    add_index :healthchecks, :enabled
    add_index :healthchecks, :last_checked_at
  end
end
