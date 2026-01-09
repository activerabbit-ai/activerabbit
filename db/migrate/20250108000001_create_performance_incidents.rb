class CreatePerformanceIncidents < ActiveRecord::Migration[8.0]
  def change
    create_table :performance_incidents do |t|
      # references already creates index by default
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true, index: false # We'll add composite index

      # Endpoint/action this incident is for (e.g., "UsersController#index")
      t.string :target, null: false

      # Incident status: open, closed
      t.string :status, null: false, default: "open"

      # Severity: warning (p95 > 750ms), critical (p95 > 1500ms)
      t.string :severity, null: false, default: "warning"

      # Timestamps for incident lifecycle
      t.datetime :opened_at, null: false
      t.datetime :closed_at

      # Performance metrics at key moments
      t.float :trigger_p95_ms, null: false    # p95 when incident opened
      t.float :peak_p95_ms                     # worst p95 during incident
      t.float :resolve_p95_ms                  # p95 when incident closed
      t.float :threshold_ms, null: false       # threshold that was breached

      # Warm-up tracking: consecutive breach count
      t.integer :breach_count, null: false, default: 0

      # Environment (production, staging, etc.)
      t.string :environment, default: "production"

      # Notification flags
      t.boolean :open_notification_sent, default: false
      t.boolean :close_notification_sent, default: false

      t.timestamps
    end

    # Index for finding open incidents per project/target
    add_index :performance_incidents, [:project_id, :target, :status]
    add_index :performance_incidents, [:project_id, :status]
    add_index :performance_incidents, :opened_at
    # Note: account_id index is already created by t.references
  end
end

