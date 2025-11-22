class CreateDeploys < ActiveRecord::Migration[8.0]
  def change
    create_table :deploys do |t|
      t.references :project, null: false, foreign_key: true
      t.references :release, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.references :account, null: false, foreign_key: true

      t.string :status

      t.datetime :started_at, null: false
      t.datetime :finished_at

      t.jsonb :metadata
      t.jsonb :errors_metadata

      t.timestamps
    end
  end
end
