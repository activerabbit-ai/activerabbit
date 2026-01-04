class AddPauseColumnsToPaySubscriptions < ActiveRecord::Migration[8.0]
  def change
    add_column :pay_subscriptions, :pause_starts_at, :datetime
    add_column :pay_subscriptions, :pause_ends_at, :datetime
    add_column :pay_subscriptions, :pause_behavior, :string
    add_column :pay_subscriptions, :pause_resumes_at, :datetime
  end
end

