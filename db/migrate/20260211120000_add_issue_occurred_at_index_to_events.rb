class AddIssueOccurredAtIndexToEvents < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    return unless table_exists?(:events)

    # Speed up queries like:
    # - issue.events.where("occurred_at > ?", 24.hours.ago).count
    # - events.where(issue_id: ids).where("occurred_at > ?", ...).group(:issue_id).count
    add_index :events,
              [:issue_id, :occurred_at],
              algorithm: :concurrently,
              if_not_exists: true
  end
end
