class AddAccountIdToProjects < ActiveRecord::Migration[8.0]
  def change
    add_reference :projects, :account, null: false, foreign_key: true
  end
end
