class OnboardingController < ApplicationController
  before_action :authenticate_user!
  before_action :redirect_if_has_projects, except: [:welcome]
  layout 'admin'

  def welcome
    # Welcome page - always accessible
    @user = current_user
    @account = current_account
  end

  def new_project
    @project = current_user.projects.build
  end

  def create_project
    @project = current_user.projects.build(project_params)
    @project.environment = 'production' # Default environment

    if @project.save
      # Generate API token for the new project
      @project.generate_api_token!

      # Create default alert rules
      @project.create_default_alert_rules!

      redirect_to dashboard_path, notice: 'Welcome to ActiveRabbit! Your project has been created successfully.'
    else
      render :new_project
    end
  end

  private

  def project_params
    params.require(:project).permit(:name, :url, :description)
  end

  def redirect_if_has_projects
    if current_user.projects.any?
      redirect_to dashboard_path
    end
  end
end
