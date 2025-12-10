class AddInvitedByToUsers < ActiveRecord::Migration[8.0]
  def change
    add_reference :users, :invited_by, foreign_key: { to_table: :users }, null: true
  end
end
