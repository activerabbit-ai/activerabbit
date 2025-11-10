class Api::V1::ReleasesController < Api::BaseController
  # POST /api/v1/releases
  def create
    payload = sanitize_release_payload(params)

    # Validate required fields
    validate_release_payload!(payload)

    # Check if release already exists
    existing_release = @current_project.releases.find_by(
      version: payload[:version],
      environment: payload[:environment]
    )

    if existing_release
      render json: {
        error: "conflict",
        message: "Release already exists",
        data: { id: existing_release.id, version: existing_release.version }
      }, status: :conflict
      return
    end

    # Create release
    release = Release.create_from_deploy(
      project: @current_project,
      version: payload[:version],
      environment: payload[:environment],
      metadata: payload[:metadata]
    )

    render_created(
      {
        id: release.id,
        version: release.version,
        environment: release.environment,
        deployed_at: release.deployed_at
      },
      message: "Release created and regression detection scheduled"
    )
  end

  # GET /api/v1/releases
  def index
    environment = params[:environment]
    limit = [params[:limit]&.to_i || 20, 100].min # Max 100 releases

    releases = @current_project.releases.recent
    releases = releases.for_environment(environment) if environment.present?
    releases = releases.limit(limit)

    render_success(
      releases.map do |release|
        {
          id: release.id,
          version: release.version,
          environment: release.environment,
          deployed_at: release.deployed_at,
          regression_detected: release.regression_detected?,
          regression_summary: release.regression_summary
        }
      end
    )
  end

  # GET /api/v1/releases/:id
  def show
    release = @current_project.releases.find(params[:id])

    render_success({
      id: release.id,
      version: release.version,
      environment: release.environment,
      deployed_at: release.deployed_at,
      regression_detected: release.regression_detected?,
      regression_data: release.regression_data,
      metadata: release.metadata
    })
  end

  # POST /api/v1/releases/:id/trigger_regression_check
  def trigger_regression_check
    release = @current_project.releases.find(params[:id])

    # Queue regression detection
    RegressionDetectionJob.perform_async(release.id)

    render_success(
      { id: release.id },
      message: "Regression detection queued"
    )
  end

  private

  def sanitize_release_payload(params)
    {
      version: params[:version] || params["version"],
      environment: params[:environment] || params["environment"] || "production",
      metadata: params[:metadata] || params["metadata"] || {}
    }
  end

  def validate_release_payload!(payload)
    errors = []

    errors << "version is required" if payload[:version].blank?

    if errors.any?
      render json: {
        error: "validation_failed",
        message: "Invalid release payload",
        details: errors
      }, status: :unprocessable_entity
      return false
    end

    true
  end
end
