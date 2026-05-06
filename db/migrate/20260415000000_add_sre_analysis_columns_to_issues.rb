class AddSreAnalysisColumnsToIssues < ActiveRecord::Migration[8.0]
  def change
    add_column :issues, :resolution_status, :string
    add_column :issues, :sre_confidence, :integer
    add_column :issues, :root_cause, :jsonb
    add_column :issues, :fix_diff, :text
    add_column :issues, :safe_to_auto_merge, :boolean
    add_column :issues, :sre_analyzed_at, :datetime
    add_column :issues, :sre_analysis, :jsonb

    add_index :issues, :resolution_status
    add_index :issues, :sre_analyzed_at
  end
end
