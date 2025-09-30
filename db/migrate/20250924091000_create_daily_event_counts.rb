class CreateDailyEventCounts < ActiveRecord::Migration[8.0]
  def up
    create_table :daily_event_counts do |t|
      t.references :account, null: false, type: :bigint, foreign_key: true
      t.date :day, null: false
      t.integer :count, null: false, default: 0
      t.timestamps
    end
    add_index :daily_event_counts, [ :account_id, :day ], unique: true
  end

  def down
    remove_index :daily_event_counts, [ :account_id, :day ] if index_exists?(:daily_event_counts, [ :account_id, :day ])
    drop_table :daily_event_counts
  end
end
