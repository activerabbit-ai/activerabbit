class AddAccountIdToAlertRules < ActiveRecord::Migration[8.0]
  def change
    add_reference :alert_rules, :account, null: false, foreign_key: true
    add_index :alert_rules, [:account_id, :project_id]
  end
end
