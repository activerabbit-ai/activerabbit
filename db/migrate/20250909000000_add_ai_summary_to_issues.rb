class AddAiSummaryToIssues < ActiveRecord::Migration[8.0]
  def change
    add_column :issues, :ai_summary, :text
    add_column :issues, :ai_summary_generated_at, :datetime
  end
end


