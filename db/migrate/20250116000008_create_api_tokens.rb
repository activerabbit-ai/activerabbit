class CreateApiTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :api_tokens do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token, null: false
      t.boolean :active, null: false, default: true
      t.integer :usage_count, null: false, default: 0
      t.datetime :last_used_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :api_tokens, :token, unique: true
    add_index :api_tokens, :active
    add_index :api_tokens, [:project_id, :active]
  end
end
