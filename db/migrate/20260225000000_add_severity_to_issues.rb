# frozen_string_literal: true

class AddSeverityToIssues < ActiveRecord::Migration[8.0]
  def change
    add_column :issues, :severity, :string
    add_index :issues, :severity
  end
end
