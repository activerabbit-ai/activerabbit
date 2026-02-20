class ChangeDefaultPlanToTrial < ActiveRecord::Migration[8.0]
  def change
    change_column_default :accounts, :current_plan, from: "developer", to: "trial"
  end
end
