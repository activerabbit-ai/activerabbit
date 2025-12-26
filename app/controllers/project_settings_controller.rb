class ProjectSettingsController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project

  def show
    # Show project settings including Slack configuration
    @api_tokens = @project.api_tokens.active
    @preferences_by_type =
      NotificationPreference::ALERT_TYPES.index_with do |type|
        @project.notification_preferences.find_or_create_by!(
          alert_type: type
        ) do |pref|
          pref.enabled = true
          pref.frequency = "immediate"
        end
      end
  end

  def update
    ok = true

    ok &&= update_notification_settings if params[:project]&.dig(:notifications)
    ok &&= update_github_settings if params[:project]&.except(:notifications).present?
    ok &&= update_notification_preferences if params[:preferences].present?

    if ok
      redirect_to project_settings_path(@project),
                  notice: "Settings updated successfully."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def test_notification
    unless @project.notify_via_slack?
      redirect_to project_settings_path(@project),
                  alert: "Slack notifications are disabled or Slack is not configured."
      return
    end

    begin
      slack_service = SlackNotificationService.new(@project)
      slack_service.send_custom_alert(
        "🧪 *Test Notification*",
        "This is a test message from ActiveRabbit to verify your Slack integration is working correctly!",
        color: "good"
      )

      redirect_to project_settings_path(@project), notice: "Test notification sent successfully! Check your Slack channel."
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
      @project = Project.find(params[:project_id])
    else
      redirect_to dashboard_path, alert: "Project not found."
    end
  end

  def update_notification_settings
    return true unless params[:project]

    notif_params = params
      .require(:project)
      .fetch(:notifications, {})
      .permit(:enabled, channels: [:slack, :email])

    settings = @project.settings || {}
    settings["notifications"] ||= {}

    settings["notifications"]["enabled"] =
      notif_params[:enabled] == "1"

    settings["notifications"]["channels"] = {
      "slack" => notif_params.dig(:channels, :slack) == "1",
      "email" => notif_params.dig(:channels, :email) == "1"
    }

    @project.settings = settings
    @project.save
  end

  def update_github_settings
    gh_params = params.fetch(:project, {}).permit(:github_repo, :github_installation_id, :github_pat, :github_app_id, :github_app_pk, :github_app_pk_file)
    return true if gh_params.blank?

    settings = @project.settings || {}
    # Helper to set or clear a setting if the field was present in the form
    set_or_clear = lambda do |key, param_key|
      if gh_params.key?(param_key)
        value = gh_params[param_key]
        if value.present?
          settings[key] = value.is_a?(String) ? value.strip : value
        else
          settings.delete(key)
        end
      end
    end

    set_or_clear.call("github_repo", :github_repo)
    set_or_clear.call("github_installation_id", :github_installation_id)
    set_or_clear.call("github_pat", :github_pat)
    set_or_clear.call("github_app_id", :github_app_id)
    # File upload takes precedence over pasted PEM
    if gh_params[:github_app_pk_file].present?
      uploaded = gh_params[:github_app_pk_file]
      settings["github_app_pk"] = uploaded.read
    else
      set_or_clear.call("github_app_pk", :github_app_pk)
    end
    @project.settings = settings
    @project.save
  end

  def test_slack_notification
    begin
      slack_service = SlackNotificationService.new(@project)
      slack_service.send_custom_alert(
        "🧪 *Test Notification*",
        "Your Slack integration is working correctly! Settings have been saved.",
        color: "good"
      )

      redirect_to project_settings_path(@project),
                  notice: "Slack settings saved and test notification sent successfully!"
    rescue StandardError => e
      Rails.logger.error "Slack test failed: #{e.message}"
      redirect_to project_settings_path(@project),
                  alert: "Settings saved, but test notification failed: #{e.message}"
    end
  end

  def update_notification_preferences
    prefs = params[:preferences]
    return true if prefs.blank?

    prefs.each do |id, attrs|
      pref = @project.notification_preferences.find(id)
      pref.update!(frequency: attrs[:frequency])
    end

    true
  end
end
