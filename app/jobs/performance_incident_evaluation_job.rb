class PerformanceIncidentEvaluationJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 1

  LOCK_KEY = "lock:perf_incident_eval"
  LOCK_TTL = 90 # seconds — prevents cron pile-up if job takes >1 min

  # Evaluate performance metrics for all active projects
  # Called every minute by sidekiq-cron
  def perform
    # Skip if a previous run is still in progress
    locked = Sidekiq.redis { |c| c.set(LOCK_KEY, Process.pid.to_s, nx: true, ex: LOCK_TTL) }
    unless locked
      Rails.logger.info "[PerformanceIncidentEvaluation] Skipping — already running"
      return
    end

    begin
      Rails.logger.info "[PerformanceIncidentEvaluation] Starting evaluation..."

      # Query projects without tenant scoping since we're processing all accounts
      ActsAsTenant.without_tenant do
        Project.active.find_each do |project|
          ActsAsTenant.with_tenant(project.account) do
            evaluate_project(project)
          end
        rescue => e
          Rails.logger.error "[PerformanceIncidentEvaluation] Error evaluating project #{project.id}: #{e.message}"
        end
      end

      Rails.logger.info "[PerformanceIncidentEvaluation] Evaluation complete"
    ensure
      Sidekiq.redis { |c| c.del(LOCK_KEY) }
    end
  end

  private

  def evaluate_project(project)
    # Get p95 metrics from the last minute's rollups
    # Group by target (controller#action)
    recent_rollups = project.perf_rollups
                            .where(timeframe: "minute")
                            .where("timestamp > ?", 2.minutes.ago)
                            .group(:target)
                            .select(
                              :target,
                              "AVG(p95_duration_ms) as avg_p95",
                              "MAX(p95_duration_ms) as max_p95",
                              "COUNT(*) as sample_count"
                            )

    unless recent_rollups.empty?
      recent_rollups.each do |rollup|
        target = rollup.target
        current_p95 = rollup.avg_p95 || rollup.max_p95

        next unless current_p95 && current_p95 > 0

        Rails.logger.debug "[PerformanceIncidentEvaluation] #{project.slug}/#{target}: p95=#{current_p95.round(1)}ms"

        PerformanceIncident.evaluate_endpoint(
          project: project,
          target: target,
          current_p95_ms: current_p95,
          environment: project.environment || "production"
        )
      end
    else
      Rails.logger.debug "[PerformanceIncidentEvaluation] No recent rollups for project #{project.slug}"
    end

    # Always check for open incidents that might need to be closed
    # (if their targets have no recent data, assume recovered)
    check_stale_incidents(project)
  end

  # Check for open incidents with no recent data (assume recovered)
  def check_stale_incidents(project)
    project.performance_incidents.open.each do |incident|
      has_recent_data = project.perf_rollups
                               .where(target: incident.target)
                               .where("timestamp > ?", 5.minutes.ago)
                               .exists?

      unless has_recent_data
        Rails.logger.info "[PerformanceIncidentEvaluation] No recent data for open incident #{incident.target}, marking as recovered"

        # Treat as recovery with unknown p95
        PerformanceIncident.handle_recovery(
          project: project,
          target: incident.target,
          current_p95_ms: 0, # Unknown, but below threshold
          warmup_count: 1,   # Close immediately if no data
          cooldown_minutes: PerformanceIncident::DEFAULT_COOLDOWN_MINUTES,
          open_incident: incident
        )
      end
    end
  end
end
