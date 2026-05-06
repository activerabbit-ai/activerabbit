class AddAutoFixToProjectsAndIssues < ActiveRecord::Migration[7.1]
  def change
    add_column :projects, :auto_pr_weekly_cap, :integer, default: 5, null: false
    add_column :projects, :auto_pr_confidence_threshold, :integer, default: 80, null: false
    add_column :issues, :auto_fix_status, :string unless column_exists?(:issues, :auto_fix_status)
    add_index  :issues, [:project_id, :auto_fix_status]
  end
end
