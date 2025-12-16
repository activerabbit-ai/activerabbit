class CreateNotificationPreferences < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_preferences do |t|
      t.references :project, null: false, foreign_key: true
      t.string :alert_type, null: false
      t.boolean :enabled, default: true, null: false
      t.string :frequency, null: false, default: "immediate"
      t.datetime :last_sent_at

      t.timestamps
    end

    add_index :notification_preferences, [:project_id, :alert_type], unique: true
  end
end
