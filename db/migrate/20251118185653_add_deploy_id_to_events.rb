class AddDeployIdToEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :events, :deploy, foreign_key: true
  end
end
