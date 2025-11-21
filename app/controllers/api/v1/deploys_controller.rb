class Api::V1::DeploysController < Api::BaseController
  # POST api/v1/deploys
  def create
    project = Project.find_by!(slug: params[:project_slug])

    # Find or create release
    release = project.releases.find_or_initialize_by(
      version: params[:version],
      environment: params[:environment]
    )

    if release.new_record?
      release.deployed_at = params[:finished_at] || Time.current
      release.save!
    end

    user = User.find_by!(email: params[:user])

    deploy = Deploy.create!(
      account: project.account,
      project: project,
      release: release,
      user: user,
      status: params[:status],
      started_at: params[:started_at],
      finished_at: params[:finished_at]
    )

    render json: { ok: true, deploy_id: deploy.id }
  end
end
