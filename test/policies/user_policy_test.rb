require "test_helper"

class UserPolicyTest < ActiveSupport::TestCase
  # permitted_attributes tests - owner

  test "owner editing themselves permits profile fields" do
    owner = users(:owner)
    policy = UserPolicy.new(owner, owner)

    expected = [:email, :password, :password_confirmation, :current_password]
    assert_equal expected.sort, policy.permitted_attributes.sort
  end

  test "owner editing themselves does not permit super_admin" do
    owner = users(:owner)
    policy = UserPolicy.new(owner, owner)

    refute_includes policy.permitted_attributes, :super_admin
  end

  test "owner editing another user permits email and role" do
    owner = users(:owner)
    member = users(:member)
    policy = UserPolicy.new(owner, member)

    assert_equal [:email, :role].sort, policy.permitted_attributes.sort
  end

  test "owner editing another user does not permit super_admin" do
    owner = users(:owner)
    member = users(:member)
    policy = UserPolicy.new(owner, member)

    refute_includes policy.permitted_attributes, :super_admin
  end

  # permitted_attributes tests - super_admin

  test "super_admin editing themselves permits profile fields but not super_admin" do
    super_admin = users(:super_admin)
    policy = UserPolicy.new(super_admin, super_admin)

    expected = [:email, :password, :password_confirmation, :current_password]
    assert_equal expected.sort, policy.permitted_attributes.sort
    refute_includes policy.permitted_attributes, :super_admin
  end

  test "super_admin editing another user permits email, role, and super_admin" do
    super_admin = users(:super_admin)
    member = users(:member)
    policy = UserPolicy.new(super_admin, member)

    assert_equal [:email, :role, :super_admin].sort, policy.permitted_attributes.sort
  end

  # permitted_attributes tests - member

  test "member editing themselves permits profile fields" do
    member = users(:member)
    policy = UserPolicy.new(member, member)

    expected = [:email, :password, :password_confirmation, :current_password]
    assert_equal expected.sort, policy.permitted_attributes.sort
  end

  test "member editing another user returns empty array" do
    member = users(:member)
    # Create another member for this test
    other = users(:unconfirmed)
    policy = UserPolicy.new(member, other)

    assert_empty policy.permitted_attributes
  end

  # authorization - index?

  test "index allows owner" do
    owner = users(:owner)
    assert UserPolicy.new(owner, User).index?
  end

  test "index denies member" do
    member = users(:member)
    refute UserPolicy.new(member, User).index?
  end

  # authorization - create?

  test "create allows owner" do
    owner = users(:owner)
    assert UserPolicy.new(owner, User.new).create?
  end

  test "create denies member" do
    member = users(:member)
    refute UserPolicy.new(member, User.new).create?
  end

  # authorization - edit?

  test "edit allows owner to edit any user" do
    owner = users(:owner)
    member = users(:member)
    assert UserPolicy.new(owner, member).edit?
  end

  test "edit allows member to edit themselves" do
    member = users(:member)
    assert UserPolicy.new(member, member).edit?
  end

  test "edit denies member from editing others" do
    member = users(:member)
    other = users(:unconfirmed)
    refute UserPolicy.new(member, other).edit?
  end

  # authorization - update?

  test "update allows owner to update any user" do
    owner = users(:owner)
    member = users(:member)
    assert UserPolicy.new(owner, member).update?
  end

  test "update allows member to update themselves" do
    member = users(:member)
    assert UserPolicy.new(member, member).update?
  end

  test "update denies member from updating others" do
    member = users(:member)
    other = users(:unconfirmed)
    refute UserPolicy.new(member, other).update?
  end

  # authorization - destroy?

  test "destroy allows owner" do
    owner = users(:owner)
    member = users(:member)
    assert UserPolicy.new(owner, member).destroy?
  end

  test "destroy denies member" do
    member = users(:member)
    other = users(:unconfirmed)
    refute UserPolicy.new(member, other).destroy?
  end
end
