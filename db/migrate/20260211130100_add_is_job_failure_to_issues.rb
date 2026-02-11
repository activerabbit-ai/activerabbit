class AddIsJobFailureToIssues < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    return unless table_exists?(:issues)

    # Add a boolean flag so ?filter=jobs can query issues directly
    # instead of doing a subquery into the events table with JSON casting.
    unless column_exists?(:issues, :is_job_failure)
      add_column :issues, :is_job_failure, :boolean, default: false, null: false
    end

    # Add index for fast filtering
    add_index :issues, :is_job_failure,
              where: "is_job_failure = true",
              algorithm: :concurrently,
              if_not_exists: true

    # Backfill: mark issues that have job-related controller_action
    # (i.e., no "Controller#" in the name — workers/jobs don't follow that pattern)
    execute <<-SQL.squish
      UPDATE issues
      SET is_job_failure = true
      WHERE controller_action NOT LIKE '%Controller#%'
        AND controller_action IS NOT NULL
        AND is_job_failure = false
    SQL
  end

  def down
    remove_column :issues, :is_job_failure if column_exists?(:issues, :is_job_failure)
  end
end
