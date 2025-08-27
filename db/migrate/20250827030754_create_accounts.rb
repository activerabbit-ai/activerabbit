class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :accounts, :name
  end
end
