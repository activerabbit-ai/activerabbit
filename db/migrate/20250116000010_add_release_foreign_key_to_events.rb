class AddReleaseForeignKeyToEvents < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :events, :releases, column: :release_id
  end
end
