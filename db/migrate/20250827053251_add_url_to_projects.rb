class AddUrlToProjects < ActiveRecord::Migration[8.0]
  def change
    add_column :projects, :url, :string
  end
end
