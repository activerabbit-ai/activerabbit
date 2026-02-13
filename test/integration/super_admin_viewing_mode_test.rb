require "test_helper"

class SuperAdminViewingModeTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @super_admin = users(:super_admin)
    @other_account = accounts(:other_account)
  end

  # Read-only mode enforcement

  test "allows GET requests in viewing mode" do
    sign_in @super_admin
    post "/accounts/#{@other_account.id}/switch"

    get dashboard_path

    assert_response :success
  end

  test "blocks POST requests in viewing mode" do
    sign_in @super_admin
    post "/accounts/#{@other_account.id}/switch"

    post projects_path, params: { project: { name: "New Project", environment: "production" } }

    assert_redirected_to dashboard_path
    assert_includes flash[:alert], "View-only mode"
  end

  test "allows exit viewing mode" do
    sign_in @super_admin
    post "/accounts/#{@other_account.id}/switch"

    delete super_admin_exit_accounts_path

    assert_redirected_to super_admin_accounts_path
    assert_nil flash[:alert]
  end

  # Normal mode

  test "allows POST requests in normal mode" do
    sign_in @super_admin

    post projects_path, params: { project: { name: "New Project", environment: "production" } }

    # Should not be blocked by read-only mode
    refute_includes flash[:alert].to_s, "View-only mode"
  end

  # Viewing banner visibility

  test "does not show viewing banner in normal mode" do
    sign_in @super_admin

    get dashboard_path

    refute_includes response.body, "SUPER ADMIN MODE"
  end

  test "shows viewing banner when viewing another account" do
    sign_in @super_admin
    post "/accounts/#{@other_account.id}/switch"

    get dashboard_path

    assert_includes response.body, "Viewing:"
    assert_includes response.body, @other_account.name
    assert_includes response.body, "SUPER ADMIN MODE"
  end

  # Regular user restrictions

  test "regular user cannot access super admin accounts page" do
    regular_owner = users(:owner)
    sign_in regular_owner

    get super_admin_accounts_path

    assert_redirected_to root_path
    assert_equal "Access denied", flash[:alert]
  end

  test "regular user cannot switch to viewing another account" do
    regular_owner = users(:owner)
    sign_in regular_owner

    post switch_super_admin_account_path(@other_account)

    assert_redirected_to root_path
    assert_nil session[:viewed_account_id]
  end

  # Sidebar link visibility

  test "super admin sees All Accounts link" do
    sign_in @super_admin

    get dashboard_path

    assert_includes response.body, "All Accounts"
    assert_includes response.body, super_admin_accounts_path
  end

  test "regular owner does not see All Accounts link" do
    regular_owner = users(:owner)
    sign_in regular_owner

    get dashboard_path

    refute_includes response.body, "All Accounts"
  end
end
