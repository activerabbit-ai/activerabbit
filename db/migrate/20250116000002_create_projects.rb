class CreateProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :projects do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :environment, null: false, default: 'production'
      t.text :description
      t.boolean :active, null: false, default: true
      t.json :settings, default: {}
      t.string :health_status, default: 'unknown'
      t.datetime :last_event_at

      t.timestamps
    end

    add_index :projects, :slug, unique: true
    add_index :projects, [:user_id, :name], unique: true
    add_index :projects, :active
    add_index :projects, :environment
  end
end
