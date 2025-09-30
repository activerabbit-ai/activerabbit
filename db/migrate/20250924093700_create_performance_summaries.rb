class CreatePerformanceSummaries < ActiveRecord::Migration[8.0]
  def change
    create_table :performance_summaries do |t|
      t.references :account, null: false, foreign_key: true, type: :bigint
      t.references :project, null: false, foreign_key: true, type: :bigint
      t.string :target, null: false
      t.text :summary
      t.datetime :generated_at
      t.timestamps
    end

    add_index :performance_summaries, [:project_id, :target], unique: true
  end
end
