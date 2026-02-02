class UserPolicy < ApplicationPolicy
  def index?
    user.owner?
  end

  def create?
    user.owner?
  end

  def edit?
    user.owner? || record == user
  end

  def update?
    user.owner? || record == user
  end

  def destroy?
    user.owner?
  end

  def invite?
    user.owner?
  end

  def avatar?
    user.owner? || record == user
  end

  def permitted_attributes
    if user.owner?
      if record == user
        [:email, :password, :password_confirmation, :current_password, :avatar]
      else
        [:email, :role]
      end
    elsif record == user
      [:email, :password, :password_confirmation, :current_password, :avatar]
    else
      []
    end
  end
end
