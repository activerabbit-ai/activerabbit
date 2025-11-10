class OnboardingController < ApplicationController
  before_action :authenticate_user!
  before_action :redirect_if_has_projects, except: [:install_gem, :verify_gem]  # Allow gem installation for additional projects
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
    @project = current_user.projects.build
  end

  def create_project
    @project = current_user.projects.build(project_params)
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
    @project = current_user.projects.find(params[:project_id])
  end

  def verify_gem
    @project = current_user.projects.find(params[:project_id])

    verification_service = GemVerificationService.new(@project)
    result = verification_service.verify_connection

    if result[:success]
      redirect_to dashboard_path,
                  notice: "Perfect! #{result[:message]} Welcome to ActiveRabbit!"
    else
      flash[:alert] = result[:error]
      flash[:error_code] = result[:error_code]
      flash[:suggestions] = result[:suggestions]
      redirect_to onboarding_install_gem_path(@project)
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :url, :description, :tech_stack)
  end

  def redirect_if_has_projects
    if current_user.projects.any?
      redirect_to dashboard_path
    end
  end
end
