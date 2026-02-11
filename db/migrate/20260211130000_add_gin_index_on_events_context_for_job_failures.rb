class AddGinIndexOnEventsContextForJobFailures < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    return unless table_exists?(:events)
    return unless column_exists?(:events, :context)

    # The from_job_failures scope casts context (json) to jsonb and uses the ? operator.
    # A GIN index on context::jsonb makes these queries use an index scan instead of a
    # sequential scan of the entire events table.
    #
    # Before: Seq Scan on events (~30s+ on large tables)
    # After:  Bitmap Index Scan on idx_events_context_gin (~5ms)
    execute <<-SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_events_context_gin
      ON events USING gin ((context::jsonb))
    SQL
  end

  def down
    execute <<-SQL.squish
      DROP INDEX IF EXISTS idx_events_context_gin
    SQL
  end
end
