class OnboardingWizardController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :set_current_project_from_slug, only: [:start_sentry_import]
  layout "admin"

  helper_method :step_partial_suffix

  def show
    @project = current_account.projects.order(:created_at).last
    @step = decide_step(@project)
    @github_install_url = Github::InstallationService.app_install_url(project_id: @project&.id) if @step == 2
    render :show
  end

  def complete
    redirect_to inbox_path
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

  def verify_sentry_token
    client = Sentry::Client.new(params[:token])
    unless client.verify_token
      render turbo_stream: turbo_stream.replace("sentry_card",
        partial: "onboarding_wizard/step_1_sentry_form",
        locals: { error: "Invalid token. Check that scopes include org:read, project:read, event:read." })
      return
    end
    projects = client.list_projects
    if projects.empty?
      render turbo_stream: turbo_stream.replace("sentry_card",
        partial: "onboarding_wizard/step_1_sentry_form",
        locals: { error: "Token valid but no projects accessible." })
      return
    end
    render turbo_stream: turbo_stream.replace("sentry_card",
      partial: "onboarding_wizard/step_1_sentry_project_picker",
      locals: { projects: projects, token: params[:token], app_name: params[:app_name] })
  end

  def start_sentry_import
    name = params[:app_name].presence || params[:project_slug]
    project = current_account.projects.create!(
      name: name,
      environment: "production",
      tech_stack: map_platform_to_tech_stack(params[:platform]),
      settings: {
        "sentry_org_slug" => params[:org_slug],
        "sentry_project_slug" => params[:project_slug],
        "sentry_auth_token" => params[:token],
        "sentry_webhook_secret" => SecureRandom.hex(32)
      }
    )
    project.generate_api_token!
    project.create_default_alert_rules!
    Sentry::ImportProjectJob.perform_later(project.id)
    redirect_to onboarding_path
  end

  def step_partial_suffix(step)
    { 1 => "source", 2 => "github", 3 => "status" }.fetch(step)
  end

  private

  def map_platform_to_tech_stack(platform)
    {
      "ruby" => "rails", "ruby-rails" => "rails", "javascript" => "nodejs",
      "javascript-react" => "nodejs", "node" => "nodejs",
      "python" => "python", "go" => "go", "java" => "java"
    }[platform.to_s] || "rails"
  end

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
