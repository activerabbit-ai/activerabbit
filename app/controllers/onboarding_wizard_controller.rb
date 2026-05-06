class OnboardingWizardController < ApplicationController
  before_action :authenticate_user!
  layout "admin"

  helper_method :step_partial_suffix

  def show
    @project = current_account.projects.order(:created_at).last
    @step = decide_step(@project)
    render :show
  end

  def submit_source
    if params[:preview].present?
      preview_card
    elsif params[:source] == "sdk"
      create_sdk_project
    else
      head :bad_request
    end
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

  def preview_card
    case params[:preview]
    when "sentry"
      render turbo_stream: turbo_stream.replace("sentry_card",
        partial: "onboarding_wizard/step_1_sentry_form")
    when "sdk"
      render turbo_stream: turbo_stream.replace("sdk_card",
        partial: "onboarding_wizard/step_1_sdk_snippet")
    else
      head :bad_request
    end
  end

  def create_sdk_project
    name = params[:app_name].presence || "My App"
    project = current_account.projects.create!(
      name: name,
      environment: "production",
      tech_stack: "rails"
    )
    project.generate_api_token!
    project.create_default_alert_rules!
    redirect_to onboarding_path
  end
end
