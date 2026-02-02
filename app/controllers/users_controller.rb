class UsersController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :require_owner!, only: [:create, :destroy]

  skip_before_action :check_onboarding_needed, only: [:new, :create, :destroy]
  skip_before_action :set_current_tenant, only: [:new]
  skip_before_action :set_current_project_from_slug, only: [:new, :create, :destroy]
  skip_before_action :check_quota_exceeded, only: [:new, :create, :destroy]

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

    # Only allow role assignment if current user is owner
    if current_user.owner? && params.dig(:user, :role).present?
      @user.role = params.dig(:user, :role)
    end

    authorize @user

    unless @user.save
      render :new, status: :unprocessable_content
      return
    end

    # Generate reset token and send welcome email (not generic reset password)
    raw_token, enc_token = Devise.token_generator.generate(User, :reset_password_token)
    @user.update_columns(
      reset_password_token: enc_token,
      reset_password_sent_at: Time.current
    )
    SendWelcomeEmailJob.perform_async(@user.id, raw_token)

    redirect_to users_path, notice: "User invited"
  end

  def update
    @user = User.find(params[:id])
    authorize @user

    update_params = permitted_attributes(@user)

    if @user == current_user
      if update_params[:password].present?
        if update_params[:current_password].blank?
          @user.errors.add(:current_password, "can't be blank")
          render :edit
          return
        end

        success = @user.update_with_password(update_params)
      else
        update_params.delete(:password)
        update_params.delete(:password_confirmation)
        update_params.delete(:current_password)

        success = @user.update(update_params)
      end
    else
      update_params.delete(:password)
      update_params.delete(:password_confirmation)
      update_params.delete(:current_password)
      success = @user.update(update_params)
    end

    if success
      if @user == current_user
        redirect_to settings_path, notice: "Profile updated successfully."
      else
        redirect_to users_path, notice: "User updated successfully."
      end
    else
      render :edit
    end
  end

  def destroy
    @user = User.find(params[:id])
    authorize @user

    # Prevent deleting yourself
    if @user == current_user
      redirect_to users_path, alert: "You cannot delete yourself."
      return
    end

    # Prevent deleting the last owner
    if @user.owner? && current_account.users.where(role: "owner").count <= 1
      redirect_to users_path, alert: "Cannot delete the last owner."
      return
    end

    if @user.destroy
      redirect_to users_path, notice: "User deleted successfully."
    else
      redirect_to users_path, alert: "Failed to delete user: #{@user.errors.full_messages.join(', ')}"
    end
  end

  def destroy_avatar
    @user = User.find(params[:id])
    authorize @user, :avatar?

    @user.avatar.purge_later if @user.avatar.attached?
    redirect_to edit_user_path(@user), notice: "Avatar deleted successfully."
  end

  def disconnect_provider
    @user = User.find(params[:id])
    authorize @user, :disconnect_provider?

    provider = params[:provider]
    
    unless %w[github google_oauth2].include?(provider)
      redirect_to edit_user_path(@user), alert: "Invalid provider."
      return
    end

    unless @user.provider == provider
      redirect_to edit_user_path(@user), alert: "This provider is not connected."
      return
    end

    @user.update(provider: nil, uid: nil)
    redirect_to edit_user_path(@user), notice: "#{provider == 'google_oauth2' ? 'Google' : 'GitHub'} account disconnected successfully."
  end

  def connect_provider
    @user = User.find(params[:id])
    authorize @user, :connect_provider?

    provider = params[:provider]
    
    unless %w[github google_oauth2].include?(provider)
      redirect_to edit_user_path(@user), alert: "Invalid provider."
      return
    end

    # Check if user already has a different provider connected
    if @user.provider.present? && @user.provider != provider
      other_provider = @user.provider == "google_oauth2" ? "Google" : "GitHub"
      redirect_to edit_user_path(@user), alert: "You already have #{other_provider} connected. Disconnect it first to connect another provider."
      return
    end

    # Check if already connected to this provider
    if @user.provider == provider
      redirect_to edit_user_path(@user), notice: "#{provider == 'google_oauth2' ? 'Google' : 'GitHub'} is already connected."
      return
    end

    # Store in session that we want to link, not login
    session[:link_provider] = provider
    
    # Redirect to OmniAuth path (each provider has its own helper)
    case provider
    when "github"
      redirect_to user_github_omniauth_authorize_path, allow_other_host: true
    when "google_oauth2"
      redirect_to user_google_oauth2_omniauth_authorize_path, allow_other_host: true
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :current_password, :avatar)
  end

  def current_account
    current_user.account
  end

  def require_owner!
    redirect_to root_path, alert: "Not have permissions" unless current_user.owner?
  end
end
