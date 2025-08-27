class AddAccountIdToPerformanceEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :performance_events, :account, null: false, foreign_key: true
    add_index :performance_events, [:account_id, :project_id]
  end
end
