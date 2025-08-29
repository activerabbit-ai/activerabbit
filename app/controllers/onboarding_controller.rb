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

      # Redirect to gem installation step instead of dashboard
      redirect_to onboarding_install_gem_path(@project), notice: 'Project created! Now let\'s install the ActiveRabbit gem.'
    else
      render :new_project
    end
  end

  def install_gem
    @project = current_user.projects.find(params[:project_id])
  end

  def verify_gem
    @project = current_user.projects.find(params[:project_id])
    
    # Make a test API call to verify the gem is working
    test_result = test_gem_connection(@project)
    
    if test_result[:success]
      redirect_to dashboard_path, notice: 'Perfect! ActiveRabbit gem is successfully connected. Welcome to ActiveRabbit!'
    else
      redirect_to onboarding_install_gem_path(@project), 
                  alert: "Gem verification failed: #{test_result[:error]}. Please check your installation."
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

  def test_gem_connection(project)
    # Check if we've received any events from this project in the last 30 seconds
    recent_events = project.events.where('created_at > ?', 30.seconds.ago)
    
    if recent_events.any?
      { success: true, message: 'Gem is working correctly!' }
    else
      # Also check if we have any events at all (maybe they tested before)
      all_events = project.events.limit(1)
      if all_events.any?
        { success: true, message: 'Gem was previously connected and working!' }
      else
        { success: false, error: 'No events received from your application. Please ensure the gem is properly installed and configured.' }
      end
    end
  rescue => e
    { success: false, error: "Connection test failed: #{e.message}" }
  end
end
