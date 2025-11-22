class AddQuotaAlertsToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :last_quota_alert_sent_at, :jsonb
  end
end
