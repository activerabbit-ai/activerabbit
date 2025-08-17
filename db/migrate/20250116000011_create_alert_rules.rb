class CreateAlertRules < ActiveRecord::Migration[8.0]
  def change
    create_table :alert_rules do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :rule_type, null: false
      t.float :threshold_value, null: false
      t.integer :time_window_minutes, null: false, default: 60
      t.integer :cooldown_minutes, null: false, default: 60
      t.boolean :enabled, null: false, default: true
      t.json :conditions, default: {}

      t.timestamps
    end

    add_index :alert_rules, [:project_id, :rule_type]
    add_index :alert_rules, :enabled
  end
end
