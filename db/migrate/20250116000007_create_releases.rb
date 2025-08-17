class CreateReleases < ActiveRecord::Migration[8.0]
  def change
    create_table :releases do |t|
      t.references :project, null: false, foreign_key: true
      t.string :version, null: false
      t.string :environment, null: false, default: 'production'
      t.datetime :deployed_at, null: false
      t.boolean :regression_detected, default: false
      t.json :regression_data, default: {}
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index :releases, [:project_id, :version], unique: true
    add_index :releases, :deployed_at
    add_index :releases, :environment
    add_index :releases, :regression_detected
  end
end
