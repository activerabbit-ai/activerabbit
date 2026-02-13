# frozen_string_literal: true

# The dashboard runs several queries that filter events by account_id + occurred_at
# (e.g. events in the last 24 hours, ORDER BY occurred_at DESC LIMIT 10).
# Without a composite index PostgreSQL falls back to scanning the account_id index
# and sorting the entire result set, which times out for large accounts.
class AddAccountOccurredAtIndexOnEvents < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :events,
              [:account_id, :occurred_at],
              order: { occurred_at: :desc },
              name: "idx_events_account_occurred_at",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
