class GithubAppController < ApplicationController
  # Skip CSRF for webhook (POST from GitHub servers)
  skip_before_action :verify_authenticity_token, only: [:webhook]
  before_action :authenticate_user!, only: [:callback]

  # GET /github/app/callback
  # Browser redirect from GitHub after user installs the app
  def callback
    installation_id = params[:installation_id]
    setup_action = params[:setup_action] # "install" or "update"
    project_id = params[:state] # We pass project_id as state parameter

    unless installation_id.present?
      redirect_to dashboard_path, alert: "GitHub App installation failed: no installation ID received."
      return
    end

    # Find the project from state parameter or use the first project
    project = if project_id.present?
                current_account.projects.find_by(id: project_id)
    else
                current_account.projects.first
    end

    unless project
      redirect_to dashboard_path, alert: "Project not found."
      return
    end

    # Fetch installation info from GitHub to get repository details
    github_info = GithubInstallationService.new(installation_id).fetch_installation_info

    if github_info[:success]
      settings = project.settings || {}
      settings["github_installation_id"] = installation_id
      settings["github_repo"] = github_info[:repository]
      settings["github_base_branch"] = github_info[:default_branch]
      project.update(settings: settings)

      redirect_to project_settings_path(project),
                  notice: "GitHub App installed successfully! Repository: #{github_info[:repository]}"
    else
      # Still save the installation_id even if we couldn't fetch repo info
      settings = project.settings || {}
      settings["github_installation_id"] = installation_id
      project.update(settings: settings)

      redirect_to project_settings_path(project),
                  notice: "GitHub App installed. Installation ID saved. #{github_info[:error]}"
    end
  end

  # POST /github/app/webhook
  # Webhook from GitHub servers with installation event data
  def webhook
    # GitHub sends installation data as JSON in the request body
    payload = if request.content_type&.include?("application/json")
                JSON.parse(request.body.read) rescue {}
    else
                params.to_unsafe_h
    end

    action = payload["action"]
    installation = payload["installation"] || payload.dig("github_app", "installation")
    repositories = payload["repositories"] || payload.dig("github_app", "repositories")

    Rails.logger.info "[GitHub Webhook] Received action=#{action} installation_id=#{installation&.dig('id')}"

    # Handle installation events - save repository info
    if installation.present? && repositories.present? && repositories.any?
      installation_id = installation["id"].to_s
      repo = repositories.first
      repo_full_name = repo["full_name"]

      Rails.logger.info "[GitHub Webhook] Installation #{installation_id} for repo: #{repo_full_name}"

      # Find the project that has this installation_id and update with repo info
      # The callback runs first and saves installation_id, then webhook arrives with repo details
      # Use without_tenant to bypass acts_as_tenant scope (webhook has no session/user context)
      project = ActsAsTenant.without_tenant do
        Project.find_by("settings->>'github_installation_id' = ?", installation_id)
      end

      if project
        ActsAsTenant.without_tenant do
          settings = project.settings || {}
          settings["github_repo"] = repo_full_name
          # GitHub doesn't send default_branch in webhook, so we keep existing or set default
          settings["github_base_branch"] ||= "main"
          project.update(settings: settings)
        end
        Rails.logger.info "[GitHub Webhook] Updated project #{project.id} with repo: #{repo_full_name}"
      else
        Rails.logger.info "[GitHub Webhook] No project found for installation_id: #{installation_id}"
      end
    end

    # Always respond with 200 OK to acknowledge receipt
    head :ok
  end
end
