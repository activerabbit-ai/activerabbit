class UsersController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :require_owner!, only: [:create, :destroy]

  skip_before_action :check_onboarding_needed, only: [:new, :create]
  skip_before_action :set_current_tenant, only: [:new]
  skip_before_action :set_current_project_from_slug, only: [:new, :create]
  skip_before_action :check_quota_exceeded, only: [:new, :create]

  def index
    authorize User
    @users = current_account.users
  end

  def edit
    @user = User.find(params[:id])
    authorize @user
  end

  def new
    @user = User.new
    authorize @user
  end

  def create
    @user = current_account.users.new(user_params)
    @user.invited_by = current_user

    authorize @user

    unless @user.save
      render :new, status: :unprocessable_content
      return
    end

    @user.send_reset_password_instructions
    redirect_to users_path, notice: "User invited"
  end

  def update
    @user = User.find(params[:id])
    authorize @user

    if @user.update(permitted_attributes(@user))
      redirect_to users_path, notice: "User updated successfully."
    else
      render :edit
    end
  end

  def destroy
    @user = User.find(params[:id])
    authorize @user
    if @user.destroy
      redirect_to users_path, notice: "User deleted successfully."
    else
      redirect_to users_path, alert: "Failed to delete user."
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end

  def current_account
    current_user.account
  end

  def require_owner!
    redirect_to root_path, alert: "Not have permissions" unless current_user.owner?
  end
end
