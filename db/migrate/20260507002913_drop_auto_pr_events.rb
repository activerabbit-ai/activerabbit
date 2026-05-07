class DropAutoPrEvents < ActiveRecord::Migration[8.0]
  def change
    drop_table :auto_pr_events do |t|
      t.references :project, null: false, foreign_key: true
      t.references :issue,   null: false, foreign_key: true
      t.datetime   :opened_at, null: false
      t.integer    :github_pr_number, null: false
      t.string     :github_pr_url, null: false
      t.timestamps
      t.index [:project_id, :opened_at]
    end
  end
end
