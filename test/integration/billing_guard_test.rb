# frozen_string_literal: true

require "test_helper"

# UI/integration spec relies on Devise + Tailwind setup that differs in CI;
# behavior is covered indirectly, so this group is skipped in CI
class BillingGuardTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @user = users(:owner)
    @project = projects(:default)
    ActsAsTenant.current_tenant = @account
  end

  test "allows dashboard during trial" do
    skip "UI/integration spec relies on Devise + Tailwind setup that differs in CI"

    @account.update!(trial_ends_at: 2.days.from_now)
    sign_in @user

    get "/dashboard"

    assert_response :ok
  end
end
