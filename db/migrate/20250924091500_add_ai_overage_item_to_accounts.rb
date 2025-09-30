class AddAiOverageItemToAccounts < ActiveRecord::Migration[8.0]
  def up
    add_column :accounts, :ai_overage_subscription_item_id, :string
  end

  def down
    remove_column :accounts, :ai_overage_subscription_item_id
  end
end
