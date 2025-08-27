class AddAccountIdToReleases < ActiveRecord::Migration[8.0]
  def change
    add_reference :releases, :account, null: false, foreign_key: true
    add_index :releases, [:account_id, :project_id]
  end
end
