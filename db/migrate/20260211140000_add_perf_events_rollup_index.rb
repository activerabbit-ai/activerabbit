class AddPerfEventsRollupIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    return unless table_exists?(:performance_events)

    # The PerfRollupJob queries performance_events with
    # WHERE occurred_at BETWEEN ... AND duration_ms IS NOT NULL
    # GROUP BY project_id, target, environment, date_trunc('minute', occurred_at)
    #
    # A composite index on (project_id, target, environment, occurred_at) covers
    # the GROUP BY and the WHERE clause, replacing the seq-scan that was causing
    # the job to take 65+ seconds.
    add_index :performance_events,
              [:project_id, :target, :environment, :occurred_at],
              name: "idx_perf_events_rollup",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
