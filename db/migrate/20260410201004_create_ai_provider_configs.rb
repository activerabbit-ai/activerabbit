class CreateAiProviderConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_provider_configs do |t|
      t.references :account, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :api_key, null: false
      t.string :fast_model
      t.string :power_model
      t.boolean :active, default: false, null: false

      t.timestamps
    end
  end
end
