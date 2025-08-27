class AddAccountIdToSqlFingerprints < ActiveRecord::Migration[8.0]
  def change
    add_reference :sql_fingerprints, :account, null: false, foreign_key: true
    add_index :sql_fingerprints, [:account_id, :project_id]
  end
end
