class AddBillingFieldsToAccounts < ActiveRecord::Migration[8.0]
  def up
    change_table :accounts, bulk: true do |t|
      t.string  :current_plan, null: false, default: "developer"
      t.string  :billing_interval, null: false, default: "month"
      t.boolean :ai_mode_enabled, null: false, default: false

      t.datetime :trial_ends_at
      t.datetime :event_usage_period_start
      t.datetime :event_usage_period_end
      t.integer  :event_quota, null: false, default: 50_000
      t.integer  :events_used_in_period, null: false, default: 0

      t.string :overage_subscription_item_id
    end
  end

  def down
    change_table :accounts, bulk: true do |t|
      t.remove :current_plan, :billing_interval, :ai_mode_enabled,
               :trial_ends_at, :event_usage_period_start, :event_usage_period_end,
               :event_quota, :events_used_in_period, :overage_subscription_item_id
    end
  end
end
