class AddSettingsToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :settings, :json, default: {}
    # Note: GIN indexes on JSON require jsonb or specific operator class
    # For now, we'll skip the index since settings queries will be infrequent
  end
end
