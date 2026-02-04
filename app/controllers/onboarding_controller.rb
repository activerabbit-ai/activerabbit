class OnboardingController < ApplicationController
  before_action :authenticate_user!
  before_action :redirect_if_has_projects, except: [:install_gem, :verify_gem, :setup_github]  # Allow gem installation for additional projects
  layout "admin"

  def welcome
    # Welcome page - only for users without projects
    @user = current_user
    @account = current_account
  end

  def connect_github
    # Placeholder endpoint to handle GitHub App installation callback
    installation_id = params[:installation_id]
    project = current_account.projects.first
    if installation_id.present? && project
      settings = project.settings || {}
      settings["github_installation_id"] = installation_id
      project.update(settings: settings)
      redirect_to project_settings_path(project), notice: "GitHub connected. Installation ID saved."
    else
      redirect_to dashboard_path, alert: "Failed to connect GitHub."
    end
  end

  def new_project
    @project = current_account.projects.build
  end

  def create_project
    @project = current_account.projects.build(project_params)
    @project.environment = "production" # Default environment

    if @project.save
      # Generate API token for the new project
      @project.generate_api_token!

      # Create default alert rules
      @project.create_default_alert_rules!

      # Redirect to gem installation step instead of dashboard
      redirect_to onboarding_install_gem_path(@project), notice: "Project created! Now let's install the ActiveRabbit gem."
    else
      render :new_project
    end
  end

  def install_gem
    @project = current_account.projects.find(params[:project_id])
  end
rescue ActiveRecord::RecordNotFound
  redirect_to onboarding_path, alert: "Project not found or access denied"

  def verify_gem
    @project = current_account.projects.find(params[:project_id])

    verification_service = GemVerificationService.new(@project)
    result = verification_service.verify_connection

    if result[:success]
      # Redirect to GitHub setup step instead of dashboard
      redirect_to onboarding_setup_github_path(@project),
                  notice: "Perfect! #{result[:message]} Now let's connect your GitHub repository."
    else
      flash[:alert] = result[:error]
      flash[:error_code] = result[:error_code]
      flash[:suggestions] = result[:suggestions]
      redirect_to onboarding_install_gem_path(@project)
    end
  end

  def setup_github
    @project = current_account.projects.find(params[:project_id])
    @github_install_url = Github::InstallationService.app_install_url(project_id: @project.id)
    @github_connected = @project.settings&.dig("github_installation_id").present?

    # Find other projects with GitHub connected for copy option
    @github_connected_projects = current_account.projects
      .where.not(id: @project.id)
      .select { |p| p.settings&.dig("github_installation_id").present? }

    # Handle copying GitHub settings from another project
    if request.post? && params[:copy_github_from_project_id].present?
      source_project = current_account.projects.find_by(id: params[:copy_github_from_project_id])
      if source_project&.settings&.dig("github_installation_id").present?
        settings = @project.settings || {}
        %w[github_installation_id github_repo].each do |key|
          settings[key] = source_project.settings[key] if source_project.settings[key].present?
        end
        settings["github_base_branch"] ||= "main"
        settings["github_source_branch"] ||= "main"
        @project.update(settings: settings)

        redirect_to dashboard_path, notice: "GitHub connected from #{source_project.name}! Welcome to ActiveRabbit!"
        return
      end
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :url, :description, :tech_stack)
  end

  def redirect_if_has_projects
    if current_account.projects.any?
      redirect_to dashboard_path
    end
  end
end
