class AddAccountIdToIssues < ActiveRecord::Migration[8.0]
  def change
    add_reference :issues, :account, null: false, foreign_key: true
  end
end
