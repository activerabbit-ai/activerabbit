class AddCompositeIndexesForErrorsPage < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    return unless table_exists?(:issues)

    # The errors page filters by project_id + last_seen_at and orders by last_seen_at DESC.
    # Without this composite index, PostgreSQL does a bitmap scan on two separate indexes
    # and then sorts — which is very slow with millions of rows.
    add_index :issues,
              [:project_id, :last_seen_at],
              order: { last_seen_at: :desc },
              name: "idx_issues_project_last_seen",
              algorithm: :concurrently,
              if_not_exists: true

    # The summary stats query groups by status with a last_seen_at filter.
    # This composite index lets PostgreSQL do an index-only scan for the grouped count.
    add_index :issues,
              [:account_id, :status, :last_seen_at],
              name: "idx_issues_account_status_last_seen",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
