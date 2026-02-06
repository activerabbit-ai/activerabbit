require "test_helper"

class UsersIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @owner = users(:owner)
    @member = users(:member)
  end

  # DELETE /users/:id

  test "owner can delete a member" do
    sign_in @owner

    assert_difference -> { User.count }, -1 do
      delete user_path(@member)
    end

    assert_redirected_to users_path
  end

  test "owner cannot delete themselves" do
    sign_in @owner

    assert_no_difference -> { User.count } do
      delete user_path(@owner)
    end

    assert_redirected_to users_path
    assert_equal "You cannot delete yourself.", flash[:alert]
  end

  test "member cannot delete other users" do
    sign_in @member
    another_member = User.create!(
      account: @account,
      email: "another#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      role: "member",
      confirmed_at: Time.current
    )

    assert_no_difference -> { User.count } do
      delete user_path(another_member)
    end

    assert_redirected_to root_path
  end

  test "unauthenticated user redirects to login" do
    delete user_path(@member)

    assert_redirected_to new_user_session_path
  end

  # POST /users (invite)

  test "owner can create new user with member role" do
    sign_in @owner

    assert_difference -> { User.count }, 1 do
      post users_path, params: {
        user: { email: "newuser#{SecureRandom.hex(4)}@example.com", role: "member" }
      }
    end

    new_user = User.last
    assert_equal "member", new_user.role
    assert_equal @owner, new_user.invited_by
  end

  test "owner invitation generates reset password token" do
    sign_in @owner

    post users_path, params: {
      user: { email: "newuser#{SecureRandom.hex(4)}@example.com", role: "member" }
    }

    new_user = User.last
    assert new_user.reset_password_token.present?
    assert new_user.reset_password_sent_at.present?
  end

  test "regular owner cannot set super_admin on invite" do
    sign_in @owner

    post users_path, params: {
      user: { email: "newuser#{SecureRandom.hex(4)}@example.com", role: "member", super_admin: "1" }
    }

    new_user = User.last
    assert_equal false, new_user.super_admin
  end

  # Super admin user management

  test "super admin can create another super admin" do
    super_admin = users(:super_admin)
    sign_in super_admin

    post users_path, params: {
      user: { email: "newsuperadmin#{SecureRandom.hex(4)}@example.com", role: "owner", super_admin: "1" }
    }

    new_user = User.last
    assert_equal true, new_user.super_admin
  end

  test "super admin can grant super admin to another user" do
    super_admin = users(:super_admin)
    sign_in super_admin

    patch user_path(@member), params: {
      user: { super_admin: "1" }
    }

    assert @member.reload.super_admin
  end

  test "regular owner cannot grant super admin" do
    sign_in @owner

    patch user_path(@member), params: {
      user: { super_admin: "1" }
    }

    assert_equal false, @member.reload.super_admin
  end
end
