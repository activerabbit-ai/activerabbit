class AddTypeToPayCustomers < ActiveRecord::Migration[8.0]
  def up
    add_column :pay_customers, :type, :string
    add_index :pay_customers, :type
  end

  def down
    remove_index :pay_customers, :type if index_exists?(:pay_customers, :type)
    remove_column :pay_customers, :type
  end
end


