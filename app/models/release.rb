class Release < ApplicationRecord
  # Multi-tenancy setup - Release belongs to Account (tenant)
  acts_as_tenant(:account)

  belongs_to :project
  has_many :events, dependent: :nullify

  validates :version, presence: true
  validates_uniqueness_to_tenant :version, scope: :project_id
  validates :environment, presence: true

  scope :recent, -> { order(deployed_at: :desc) }
  scope :for_environment, ->(env) { where(environment: env) }

  after_create :detect_regressions

  def self.create_from_deploy(project:, version:, environment:, metadata: {})
    release = create!(
      project: project,
      account: project.account,
      version: version,
      environment: environment,
      deployed_at: Time.current,
      metadata: metadata
    )

    # Schedule regression detection (best-effort: do not fail deploy creation if job queue is down)
    begin
      RegressionDetectionJob.perform_async(release.id, release.account_id)
    rescue => e
      Rails.logger.error("[ActiveRabbit] Failed to enqueue RegressionDetectionJob (perform_async) for release=#{release.id}: #{e.class}: #{e.message}") if defined?(Rails)
    end

    release
  end

  def detect_performance_regression!
    return unless deployed_at

    # Compare performance 1 hour before and after deploy
    before_window = (deployed_at - 2.hours)..(deployed_at - 1.minute)
    after_window = (deployed_at + 1.minute)..(deployed_at + 1.hour)

    regressions = []

    # Get performance data for each target (controller action)
    targets = project.perf_rollups
                     .where(environment: environment)
                     .where(timestamp: before_window.begin..after_window.end)
                     .distinct
                     .pluck(:target)

    targets.each do |action|
      before_rollups = project.perf_rollups
                              .where(environment: environment, target: action)
                              .where(timestamp: before_window)

      after_rollups = project.perf_rollups
                             .where(environment: environment, target: action)
                             .where(timestamp: after_window)

      next if before_rollups.empty? || after_rollups.empty?

      before_p95 = before_rollups.average(:p95_duration_ms)
      after_p95 = after_rollups.average(:p95_duration_ms)

      # Detect significant regression (>20% increase and >100ms)
      if after_p95 > before_p95 * 1.2 && (after_p95 - before_p95) > 100
        regression_pct = ((after_p95 - before_p95) / before_p95 * 100).round(1)

        regressions << {
          controller_action: action,
          before_p95: before_p95.round(1),
          after_p95: after_p95.round(1),
          regression_pct: regression_pct,
          severity: calculate_regression_severity(regression_pct, after_p95 - before_p95)
        }
      end
    end

    if regressions.any?
      update!(
        regression_detected: true,
        regression_data: regressions
      )

      # Send alerts for significant regressions
      high_severity_regressions = regressions.select { |r| r[:severity] == "high" }
      if high_severity_regressions.any?
        AlertJob.perform_async(
          project.id,
          "performance_regression",
          {
            release_version: version,
            environment: environment,
            regressions: high_severity_regressions
          }
        )
      end
    end

    regressions
  end

  def has_regression?
    regression_detected?
  end

  def regression_summary
    return nil unless regression_data.present?

    total_regressions = regression_data.size
    high_severity = regression_data.count { |r| r["severity"] == "high" }

    "#{total_regressions} performance regression#{'s' if total_regressions != 1} detected" +
    (high_severity > 0 ? " (#{high_severity} high severity)" : "")
  end

  private

  def detect_regressions
    # Best-effort: if Sidekiq/Redis is down, we still want the release/deploy to persist.
    begin
      RegressionDetectionJob.perform_in(5.minutes, id, account_id)
    rescue => e
      Rails.logger.error("[ActiveRabbit] Failed to enqueue RegressionDetectionJob (perform_in) for release=#{id}: #{e.class}: #{e.message}") if defined?(Rails)
    end
  end

  def calculate_regression_severity(regression_pct, absolute_increase_ms)
    if regression_pct > 50 && absolute_increase_ms > 500
      "high"
    elsif regression_pct > 25 && absolute_increase_ms > 200
      "medium"
    else
      "low"
    end
  end
end
