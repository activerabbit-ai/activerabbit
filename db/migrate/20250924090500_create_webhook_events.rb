class CreateWebhookEvents < ActiveRecord::Migration[8.0]
  def up
    create_table :webhook_events do |t|
      t.string :provider, null: false
      t.string :event_id, null: false
      t.datetime :processed_at
      t.timestamps
    end
    add_index :webhook_events, [:provider, :event_id], unique: true, name: "idx_webhook_events_unique"
  end

  def down
    remove_index :webhook_events, name: "idx_webhook_events_unique"
    drop_table :webhook_events
  end
end
