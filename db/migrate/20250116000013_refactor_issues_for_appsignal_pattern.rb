class RefactorIssuesForAppsignalPattern < ActiveRecord::Migration[8.0]
  def change
    # Update Issues table to match AppSignal pattern
    remove_column :issues, :exception_type, :string
    remove_column :issues, :message, :text
    remove_column :issues, :request_path, :string
    remove_column :issues, :resolved_at, :datetime
    remove_column :issues, :metadata, :json

    add_column :issues, :exception_class, :string, null: false
    add_column :issues, :top_frame, :text, null: false
    add_column :issues, :sample_message, :text
    add_column :issues, :closed_at, :datetime

    # Update status values: resolved -> closed, ignored -> closed
    change_column_default :issues, :status, 'open'

    # Add indexes
    add_index :issues, :exception_class
    add_index :issues, :closed_at

    # Update Events table to be error-occurrences only
    remove_column :events, :event_type, :string
    remove_column :events, :fingerprint, :string
    remove_column :events, :payload, :json
    remove_column :events, :duration_ms, :float
    remove_column :events, :sql_queries_count, :integer
    remove_column :events, :n_plus_one_detected, :boolean

    add_column :events, :exception_class, :string, null: false
    add_column :events, :message, :text, null: false
    add_column :events, :backtrace, :text
    add_column :events, :request_method, :string
    add_column :events, :context, :json, default: {}
    add_column :events, :server_name, :string
    add_column :events, :request_id, :string

    # Add indexes
    add_index :events, :exception_class
    add_index :events, :request_id
    add_index :events, :server_name
  end
end
