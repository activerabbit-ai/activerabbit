class UsersController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :require_admin!, only: [:create, :destroy]
  
  skip_before_action :check_onboarding_needed, only: [:new, :create]
  skip_before_action :set_current_tenant, only: [:new, :create]
  skip_before_action :set_current_project_from_slug, only: [:new, :create]
  skip_before_action :check_quota_exceeded, only: [:new, :create]

  def index
    @users = User.where(invited_by: current_user)
  end

  def edit
    @user = current_user
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.invited_by = current_user

    # Создаём отдельный аккаунт для нового пользователя
    @user.account = Account.create!(
      name: "#{@user.email.split('@').first.humanize}'s Account",
      trial_ends_at: Rails.configuration.x.trial_days.days.from_now,
      current_plan: "team",
      billing_interval: "month",
      event_quota: 100_000,
      events_used_in_period: 0
    )

    if @user.save
      reset_token = @user.send_reset_password_instructions
      UserMailer.welcome_and_setup_password(user: @user, reset_token: reset_token).deliver_now
      redirect_to users_path, notice: "User created, temporary password sent via email."
    else
      render :new
    end
  end

  def update
    @user = current_user
    if @user.update(user_params)
      redirect_to @user, notice: 'Profile updated successfully.'
    else
      render :edit
    end
  end

  def destroy
    @user = User.find(params[:id])
    if @user.destroy
      redirect_to users_path, notice: 'User deleted successfully.'
    else
      redirect_to users_path, alert: 'Failed to delete user.'
    end
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :role)
  end

  def current_account
    current_user.account
  end

  def require_admin!
    redirect_to root_path, alert: "Not have permissions" unless current_user.admin?
  end
end
