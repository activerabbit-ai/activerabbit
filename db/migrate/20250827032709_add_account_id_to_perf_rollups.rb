class AddAccountIdToPerfRollups < ActiveRecord::Migration[8.0]
  def change
    add_reference :perf_rollups, :account, null: false, foreign_key: true
    add_index :perf_rollups, [:account_id, :project_id]
  end
end
