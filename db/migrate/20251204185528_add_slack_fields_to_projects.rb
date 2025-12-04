class AddSlackFieldsToProjects < ActiveRecord::Migration[8.0]
  def change
    add_column :projects, :slack_access_token, :string
    add_column :projects, :slack_team_id, :string
    add_column :projects, :slack_team_name, :string
    add_column :projects, :slack_channel_id, :string
  end
end
