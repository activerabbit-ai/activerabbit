class AddAccountIdToAlertNotifications < ActiveRecord::Migration[8.0]
  def change
    add_reference :alert_notifications, :account, null: false, foreign_key: true
    add_index :alert_notifications, [:account_id, :alert_rule_id]
  end
end
