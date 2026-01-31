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
          pref.frequency = "every_2_hours"
        end
      end

    # Find other projects in the same account that have GitHub configured
    # This allows sharing GitHub installation between projects (e.g., prod/staging)
    @github_connected_projects = current_account.projects
      .where.not(id: @project.id)
      .select { |p| p.settings&.dig("github_installation_id").present? }
  end

  def update
    ok = true

    ok &&= update_project_details if project_details_params_present?
    ok &&= update_notification_settings if params[:project]&.dig(:notifications)
    ok &&= copy_github_from_project if params[:project]&.dig(:copy_github_from_project_id).present?
    ok &&= update_github_settings if github_params_present?
    ok &&= update_fizzy_settings if fizzy_params_present?
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

      # Try to send real notification with actual project data
      latest_issue = @project.issues.recent.first

      if latest_issue
        # Send real notification about the latest issue
        slack_service.send_new_issue_alert(latest_issue)
        redirect_to project_settings_path(@project),
                    notice: "Real notification sent successfully with latest issue data! Check your Slack channel."
      else
        # If no issues, send notification with real project statistics
        issue_count = @project.issues.count
        event_count = @project.events.count
        last_event_at = @project.events.maximum(:occurred_at)

        stats_message = "Project Statistics:\n" \
                       "• Total Issues: #{issue_count}\n" \
                       "• Total Events: #{event_count}\n" \
                       "• Environment: #{@project.environment}\n"

        if last_event_at
          stats_message += "• Last Event: #{last_event_at.strftime('%Y-%m-%d %H:%M:%S UTC')}"
        else
          stats_message += "• No events recorded yet"
        end

        slack_service.send_custom_alert(
          "📊 *Project Status: #{@project.name}*",
          stats_message,
          color: "good"
        )

        redirect_to project_settings_path(@project),
                    notice: "Notification sent with real project data! Check your Slack channel."
      end
    rescue StandardError => e
      Rails.logger.error "Slack test failed: #{e.message}"
      redirect_to project_settings_path(@project), alert: "Failed to send notification: #{e.message}"
    end
  end

  def test_fizzy_sync
    unless @project.fizzy_configured?
      redirect_to project_settings_path(@project),
                  alert: "Fizzy is not configured. Please set the endpoint URL and API key."
      return
    end

    fizzy_service = FizzySyncService.new(@project)
    result = fizzy_service.test_connection

    if result[:success]
      redirect_to project_settings_path(@project),
                  notice: result[:message] || "Successfully connected to Fizzy!"
    else
      redirect_to project_settings_path(@project),
                  alert: "Fizzy test failed: #{result[:error]}"
    end
  end

  def sync_all_errors
    unless @project.fizzy_configured?
      redirect_to project_settings_path(@project),
                  alert: "Fizzy is not configured. Please set the endpoint URL and API key."
      return
    end

    # Pass force=true to bypass the auto-sync toggle (this is a manual sync)
    FizzyBatchSyncJob.perform_async(@project.id, true)

    redirect_to project_settings_path(@project),
                notice: "Fizzy sync started. Issues will be synced in the background."
  end

  private

  def set_project
    # Use @current_project set by ApplicationController for slug-based routes
    # or find by project_id for regular routes
    if @current_project
      @project = @current_project
    elsif params[:project_id].present?
      @project = current_account.projects.find(params[:project_id])
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

  def copy_github_from_project
    source_project_id = params[:project][:copy_github_from_project_id]
    return true if source_project_id.blank?

    source_project = current_account.projects.find_by(id: source_project_id)
    return false unless source_project&.settings&.dig("github_installation_id").present?

    settings = @project.settings || {}
    # Copy GitHub-related settings from source project
    %w[github_installation_id github_repo].each do |key|
      settings[key] = source_project.settings[key] if source_project.settings[key].present?
    end
    # Set default branch to main for new project (user can change it)
    settings["github_base_branch"] ||= "main"
    settings["github_source_branch"] ||= "main"

    @project.settings = settings
    @project.save
  end

  def update_github_settings
    gh_params = params.fetch(:project, {}).permit(:github_repo, :github_base_branch, :github_source_branch, :github_installation_id, :github_pat, :github_app_id, :github_app_pk, :github_app_pk_file)
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
    set_or_clear.call("github_base_branch", :github_base_branch)
    set_or_clear.call("github_source_branch", :github_source_branch)
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

  def github_params_present?
    project_params = params[:project]
    return false unless project_params

    %i[github_repo github_base_branch github_source_branch github_installation_id github_pat github_app_id github_app_pk github_app_pk_file].any? do |key|
      project_params.key?(key)
    end
  end

  def fizzy_params_present?
    project_params = params[:project]
    return false unless project_params

    %i[fizzy_endpoint_url fizzy_api_key fizzy_sync_enabled].any? do |key|
      project_params.key?(key)
    end
  end

  def project_details_params_present?
    project_params = params[:project]
    return false unless project_params

    %i[name environment slug url tech_stack description].any? do |key|
      project_params.key?(key)
    end
  end

  def update_project_details
    permitted = params.require(:project).permit(:name, :environment, :slug, :url, :tech_stack, :description)
    @project.update(permitted)
  end

  def update_fizzy_settings
    fizzy_params = params.fetch(:project, {}).permit(:fizzy_endpoint_url, :fizzy_api_key, :fizzy_sync_enabled)
    return true if fizzy_params.blank?

    # Use the concern's setter methods which handle ENV: prefix logic
    if fizzy_params.key?(:fizzy_endpoint_url) && !@project.fizzy_endpoint_from_env?
      @project.fizzy_endpoint_url = fizzy_params[:fizzy_endpoint_url]
    end

    if fizzy_params.key?(:fizzy_api_key) && !@project.fizzy_api_key_from_env?
      @project.fizzy_api_key = fizzy_params[:fizzy_api_key]
    end

    if fizzy_params.key?(:fizzy_sync_enabled)
      settings = @project.settings || {}
      settings["fizzy_sync_enabled"] = fizzy_params[:fizzy_sync_enabled] == "1"
      @project.settings = settings
    end

    @project.save
  end
end
