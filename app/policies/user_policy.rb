class UserPolicy < ApplicationPolicy
  def index?
    user.user_is_owner?
  end

  def update?
    user.user_is_owner? || record.id == user.id
  end

  def destroy?
    user.user_is_owner?
  end

  def invite?
    user.user_is_owner?
  end

  private

  def user_is_owner?
    user.role == "owner"
  end
end
