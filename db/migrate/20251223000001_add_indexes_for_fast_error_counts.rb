class AddIndexesForFastErrorCounts < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    return unless table_exists?(:events)
    return unless column_exists?(:events, :account_id)

    # Speed up queries like:
    # - Event.where(project_id: ...).where('occurred_at > ?')
    # - Event.where(project_id: ..., controller_action: ...).where('occurred_at > ?')
    add_index :events,
              [:account_id, :project_id, :occurred_at],
              algorithm: :concurrently,
              if_not_exists: true

    add_index :events,
              [:account_id, :project_id, :controller_action, :occurred_at],
              algorithm: :concurrently,
              if_not_exists: true
  end
end


