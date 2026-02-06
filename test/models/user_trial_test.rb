require "test_helper"

class UserTrialTest < ActiveSupport::TestCase
  test "creating user creates account with trial" do
    # Skip default tenant during this test since we're creating a new account
    ActsAsTenant.without_tenant do
      user = User.create!(
        email: "newtrial#{SecureRandom.hex(4)}@example.com",
        password: "Password1!",
        confirmed_at: Time.current  # Skip Devise confirmation
      )

      account = user.account

      assert account.present?
      assert_in_delta Rails.configuration.x.trial_days.days.from_now, account.trial_ends_at, 5.seconds
      assert_equal "team", account.current_plan
      assert_equal "month", account.billing_interval
    end
  end
end
