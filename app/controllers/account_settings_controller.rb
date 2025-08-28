class AccountSettingsController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!
  before_action :ensure_account_access

  def show
    @account = current_account
  end

  def update
    @account = current_account

    if update_slack_settings
      if params[:test_slack] == 'true'
        test_slack_notification
      else
        redirect_to account_settings_path, notice: 'Account Slack settings updated successfully.'
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  def test_notification
    @account = current_account

    unless @account.slack_configured?
      redirect_to account_settings_path, alert: 'Slack webhook URL must be configured first.'
      return
    end

    begin
      slack_service = AccountSlackNotificationService.new(@account)
      slack_service.send_custom_alert(
        "🧪 *Test Notification*",
        "This is a test message from ActiveRabbit to verify your account-wide Slack integration is working correctly!\n\n" +
        "Account: #{@account.name}\n" +
        "User: #{current_user.email}",
        color: 'good'
      )

      redirect_to account_settings_path, notice: 'Test notification sent successfully! Check your Slack channel.'
    rescue StandardError => e
      Rails.logger.error "Account Slack test failed: #{e.message}"
      redirect_to account_settings_path, alert: "Failed to send test notification: #{e.message}"
    end
  end

  def update_user_preferences
    @account = current_account
    preferences = params.require(:preferences).permit(
      :error_notifications,
      :performance_notifications,
      :n_plus_one_notifications,
      :new_issue_notifications,
      :personal_channel
    )

    # Convert checkbox values to booleans
    preferences.each do |key, value|
      next if key == 'personal_channel'
      preferences[key] = value == '1'
    end

    @account.update_user_notification_preferences(current_user, preferences)
    redirect_to account_settings_path, notice: 'Your notification preferences have been updated.'
  end

  private

  def ensure_account_access
    # Users can only modify their own account settings
    # In the future, could add admin role checks here
    redirect_to root_path, alert: 'Access denied.' unless current_account
  end

  def update_slack_settings
    slack_params = params.require(:account).permit(:slack_webhook_url, :slack_channel, :slack_notifications_enabled)

    # Update individual settings
    @account.slack_webhook_url = slack_params[:slack_webhook_url]
    @account.slack_channel = slack_params[:slack_channel]

    # Handle checkbox for notifications enabled
    if slack_params[:slack_notifications_enabled] == '1'
      @account.settings = (@account.settings || {}).merge('slack_notifications_enabled' => true)
    else
      @account.settings = (@account.settings || {}).merge('slack_notifications_enabled' => false)
    end

    @account.save
  end

  def test_slack_notification
    begin
      slack_service = AccountSlackNotificationService.new(@account)
      slack_service.send_custom_alert(
        "🧪 *Test Notification*",
        "Your account-wide Slack integration is working correctly! Settings have been saved.\n\n" +
        "Account: #{@account.name}\n" +
        "Configured by: #{current_user.email}",
        color: 'good'
      )

      redirect_to account_settings_path,
                  notice: 'Account Slack settings saved and test notification sent successfully!'
    rescue StandardError => e
      Rails.logger.error "Account Slack test failed: #{e.message}"
      redirect_to account_settings_path,
                  alert: "Settings saved, but test notification failed: #{e.message}"
    end
  end
end
