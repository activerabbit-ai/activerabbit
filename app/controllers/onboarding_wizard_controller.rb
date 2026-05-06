class OnboardingWizardController < ApplicationController
  before_action :authenticate_user!
  layout "admin"

  helper_method :step_partial_suffix

  def show
    @project = current_account.projects.order(:created_at).last
    @step = decide_step(@project)
    render :show
  end

  def step_partial_suffix(step)
    { 1 => "source", 2 => "github", 3 => "status" }.fetch(step)
  end

  private

  def decide_step(project)
    return 1 if project.nil?
    return 2 if project.settings.to_h["github_installation_id"].blank?
    3
  end
end
