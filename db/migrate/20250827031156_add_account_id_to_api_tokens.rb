class AddAccountIdToApiTokens < ActiveRecord::Migration[8.0]
  def change
    add_reference :api_tokens, :account, null: false, foreign_key: true
  end
end
