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

  def permitted_attributes
    if user.owner?
      if record == user
        [:email, :password, :password_confirmation, :current_password]
      else
        [:role]
      end
    elsif record == user
      [:email, :password, :password_confirmation, :current_password]
    else
      []
    end
  end
end
