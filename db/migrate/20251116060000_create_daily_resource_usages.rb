class CreateDailyResourceUsages < ActiveRecord::Migration[8.0]
  def change
    create_table :daily_resource_usages do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.date :day, null: false
      t.integer :errors_count
      t.integer :ai_summaries_count
      t.integer :pull_requests_count
      t.integer :uptime_monitors_count
      t.integer :status_pages_count

      t.timestamps
    end

    # Composite index on account_id and day (covers both single account_id queries and composite queries)
    add_index :daily_resource_usages, [:account_id, :day], unique: true
  end
end

