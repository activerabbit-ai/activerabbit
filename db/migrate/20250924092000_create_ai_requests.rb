class CreateAiRequests < ActiveRecord::Migration[8.0]
  def up
    create_table :ai_requests do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.string :subscription_id
      t.string :request_type
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :ai_requests, [ :account_id, :occurred_at ]
    add_index :ai_requests, :user_id
  end

  def down
    remove_index :ai_requests, :user_id if index_exists?(:ai_requests, :user_id)
    remove_index :ai_requests, [ :account_id, :occurred_at ] if index_exists?(:ai_requests, [ :account_id, :occurred_at ])
    drop_table :ai_requests
  end
end
