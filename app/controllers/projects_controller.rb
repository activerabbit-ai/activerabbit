class ProjectsController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project, only: [:show, :edit, :update, :destroy, :regenerate_token]
  before_action :check_project_quota, only: [:new, :create]

  def index
    # Show all projects for the current account
    @projects = current_account.projects.includes(:api_tokens, :issues, :events, :user)
                               .order(:name)

    # Stats for each project
    @project_stats = {}
    @projects.each do |project|
      @project_stats[project.id] = {
        issues_count: project.issues.open.count,
        events_today: project.events.where("created_at > ?", 24.hours.ago).count,
        health_status: project.computed_health_status
      }
    end
  end

  def show
    # Project show is intentionally not used; send users to the project Errors page instead.
    redirect_to(project_slug_errors_path(@project.slug)) and return
  end

  def new
    @project = current_user.projects.build
  end

  def create
    @project = current_user.projects.build(project_params)

    if @project.save
      @project.generate_api_token!
      @project.create_default_alert_rules!

      # For additional projects, also show gem installation instructions
      redirect_to onboarding_install_gem_path(@project), notice: "Project created! Now let's set up monitoring for this project."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @project.update(project_params)
      redirect_to project_slug_errors_path(@project.slug), notice: "Project updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    redirect_to dashboard_path, notice: "Project deleted successfully."
  end

  def regenerate_token
    @project.api_tokens.active.update_all(active: false, revoked_at: Time.current)
    new_token = @project.generate_api_token!

    redirect_to project_slug_errors_path(@project.slug),
                notice: "New API token generated: #{new_token.mask_token}"
  end



  private

  def set_project
    @project = current_account.projects.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :description, :environment, :active, :url, :tech_stack, settings: {})
  end

  def check_project_quota
    return if current_account.within_quota?(:projects)

    flash[:alert] = "You've reached your project limit (#{current_account.projects_quota} projects on #{current_account.effective_plan_name} plan). Please upgrade your plan to add more projects."
    redirect_to plan_path
  end
end
