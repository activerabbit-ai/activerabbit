class CreateAlertNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :alert_notifications do |t|
      t.references :alert_rule, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.string :notification_type, null: false
      t.string :status, null: false, default: 'pending'
      t.json :payload, null: false
      t.datetime :sent_at
      t.datetime :failed_at
      t.text :error_message

      t.timestamps
    end

    add_index :alert_notifications, :status
    add_index :alert_notifications, :notification_type
    add_index :alert_notifications, :created_at
  end
end
