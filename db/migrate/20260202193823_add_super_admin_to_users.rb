class AddSuperAdminToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :super_admin, :boolean, default: false, null: false
    add_index :users, :super_admin
  end
end
