class AddAccountIdToEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :events, :account, null: false, foreign_key: true
    add_index :events, [:account_id, :project_id]
  end
end
