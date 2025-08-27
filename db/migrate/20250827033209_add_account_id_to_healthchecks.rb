class AddAccountIdToHealthchecks < ActiveRecord::Migration[8.0]
  def change
    add_reference :healthchecks, :account, null: false, foreign_key: true
    add_index :healthchecks, [:account_id, :project_id]
  end
end
