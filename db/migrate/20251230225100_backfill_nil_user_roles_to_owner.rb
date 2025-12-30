class BackfillNilUserRolesToOwner < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      UPDATE users
      SET role = 'owner'
      WHERE role IS NULL
    SQL
  end

  def down
  end
end
