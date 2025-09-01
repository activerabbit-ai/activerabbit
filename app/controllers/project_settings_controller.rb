class ProjectSettingsController < ApplicationController
  layout 'admin'
  before_action :authenticate_user!
  before_action :set_project

  def show
    # Show project settings including Slack configuration
  end

  def update
    if update_slack_settings
      if params[:test_slack] == 'true'
        test_slack_notification
      else
        redirect_to project_settings_path(@project), notice: 'Slack settings updated successfully.'
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  def test_notification
    unless @project.slack_configured?
      redirect_to project_settings_path(@project), alert: 'Slack webhook URL must be configured first.'
      return
    end

    begin
      slack_service = SlackNotificationService.new(@project)
      slack_service.send_custom_alert(
        "🧪 *Test Notification*",
        "This is a test message from ActiveRabbit to verify your Slack integration is working correctly!",
        color: 'good'
      )

      redirect_to project_settings_path(@project), notice: 'Test notification sent successfully! Check your Slack channel.'
    rescue StandardError => e
      Rails.logger.error "Slack test failed: #{e.message}"
      redirect_to project_settings_path(@project), alert: "Failed to send test notification: #{e.message}"
    end
  end

  private

  def set_project
    # Use @current_project set by ApplicationController for slug-based routes
    # or find by project_id for regular routes
    if @current_project
      @project = @current_project
    elsif params[:project_id].present?
      @project = current_user.projects.find(params[:project_id])
    else
      redirect_to dashboard_path, alert: "Project not found."
    end
  end

  def update_slack_settings
    slack_params = params.require(:project).permit(:slack_webhook_url, :slack_channel, :slack_notifications_enabled)

    # Update individual settings
    @project.slack_webhook_url = slack_params[:slack_webhook_url]
    @project.slack_channel = slack_params[:slack_channel]

    # Handle checkbox for notifications enabled
    if slack_params[:slack_notifications_enabled] == '1'
      @project.settings = @project.settings.merge('slack_notifications_enabled' => true)
    else
      @project.settings = @project.settings.merge('slack_notifications_enabled' => false)
    end

    @project.save
  end

  def test_slack_notification
    begin
      slack_service = SlackNotificationService.new(@project)
      slack_service.send_custom_alert(
        "🧪 *Test Notification*",
        "Your Slack integration is working correctly! Settings have been saved.",
        color: 'good'
      )

      redirect_to project_settings_path(@project),
                  notice: 'Slack settings saved and test notification sent successfully!'
    rescue StandardError => e
      Rails.logger.error "Slack test failed: #{e.message}"
      redirect_to project_settings_path(@project),
                  alert: "Settings saved, but test notification failed: #{e.message}"
    end
  end
end
