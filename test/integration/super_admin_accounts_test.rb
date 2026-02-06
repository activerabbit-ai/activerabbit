require "test_helper"

class SuperAdminAccountsTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @super_admin = users(:super_admin)
    @regular_owner = users(:owner)
    @other_account = accounts(:other_account)
  end

  # GET /accounts

  test "super admin can access accounts list" do
    sign_in @super_admin

    get "/accounts"

    assert_response :success
    assert_includes response.body, @account.name
  end

  test "regular owner cannot access accounts list" do
    sign_in @regular_owner

    get "/accounts"

    assert_redirected_to "/"
    assert_equal "Access denied", flash[:alert]
  end

  test "unauthenticated user redirects to login" do
    get "/accounts"

    assert_redirected_to "/signin"
  end

  # GET /accounts/:id

  test "super admin can view account details" do
    sign_in @super_admin

    get "/accounts/#{@other_account.id}"

    assert_response :success
    assert_includes response.body, @other_account.name
  end

  test "regular owner cannot view account details" do
    sign_in @regular_owner

    get "/accounts/#{@other_account.id}"

    assert_redirected_to "/"
    assert_equal "Access denied", flash[:alert]
  end

  # POST /accounts/:id/switch

  test "super admin can switch to viewing another account" do
    sign_in @super_admin

    post "/accounts/#{@other_account.id}/switch"

    assert_equal @other_account.id, session[:viewed_account_id]
    assert_redirected_to "/dashboard"
    assert_includes flash[:notice], @other_account.name
  end

  test "regular owner cannot switch accounts" do
    sign_in @regular_owner

    post "/accounts/#{@other_account.id}/switch"

    assert_redirected_to "/"
    assert_nil session[:viewed_account_id]
  end

  # DELETE /accounts/exit

  test "super admin can exit viewing mode" do
    sign_in @super_admin
    post "/accounts/#{@other_account.id}/switch"

    assert_equal @other_account.id, session[:viewed_account_id]

    delete "/accounts/exit"

    assert_nil session[:viewed_account_id]
    assert_redirected_to "/accounts"
    assert_includes flash[:notice], "Returned to your account"
  end
end
