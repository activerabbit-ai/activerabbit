class IssueAlertJob
  include Sidekiq::Job
  sidekiq_options queue: :alerts, retry: 2

  # Minimum rate limit (5 minutes) to prevent spam even if user sets "immediate"
  MIN_RATE_LIMIT_MINUTES = 5

  # Thread-safe Redis access
  # - In production: uses Rails.cache.redis (connection pool)
  # - In test: uses simple Redis connection (or mock)
  def self.redis_pool
    @redis_pool ||= if Rails.cache.respond_to?(:redis)
      Rails.cache.redis
    else
      Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/1")
    end
  end

  # Execute a block with a Redis connection from the pool
  # Handles both ConnectionPool (production) and direct Redis (test) cases
  def self.with_redis(&block)
    pool = redis_pool
    if pool.respond_to?(:with)
      pool.with(&block)
    else
      yield pool
    end
  end

  def perform(issue_id, tenant_id)
    ActsAsTenant.with_tenant(Account.find(tenant_id)) do
      issue = Issue.find(issue_id)
      project = issue.project
      latest_release = project.releases.recent.first  # Cache to avoid duplicate queries

      # Check if this is first occurrence after a deploy (first_in_deploy mode)
      first_in_deploy = first_occurrence_in_deploy?(issue, latest_release)

      # Check error frequency rules (with per-fingerprint rate limiting from UI preference)
      check_error_frequency_with_rate_limit(issue, project)

      # New issue alerts (with per-fingerprint dedup using UI preference)
      handle_new_issue_alert(issue, project, first_in_deploy, latest_release)
    end
  end

  private

  # Check if this error qualifies as "first in deploy"
  # (issue was first seen after latest deploy, or was closed before and reopened)
  def first_occurrence_in_deploy?(issue, latest_release)
    return false unless latest_release&.deployed_at

    # First occurrence if issue was created after the deploy
    if issue.first_seen_at && issue.first_seen_at >= latest_release.deployed_at
      return true
    end

    # Recurrence: issue was closed before deploy and is now reopening
    if issue.closed_at && issue.closed_at < latest_release.deployed_at
      return true
    end

    false
  end

  # Error frequency rules with per-fingerprint rate limiting
  def check_error_frequency_with_rate_limit(issue, project)
    pref = project.notification_pref_for("error_frequency")
    rate_limit_minutes = frequency_to_minutes(pref&.frequency)

    AlertRule.check_error_frequency_rules(issue, rate_limit_minutes: rate_limit_minutes)
  end

  # Handle new issue alerts with per-fingerprint dedup
  # Rate limit is based on user's UI preference
  def handle_new_issue_alert(issue, project, first_in_deploy, latest_release)
    pref = project.notification_pref_for("new_issue")

    # Handle special frequency modes
    case pref&.frequency
    when "first_in_deploy"
      # Only alert if this is the first occurrence in this deploy
      return unless first_in_deploy
    when "after_close"
      # Only alert if issue was previously closed (recurrence)
      return unless issue.closed_at.present?
    else
      # For all other modes: only alert for truly new issues or recurrences
      # Issue is "new" if it has very few occurrences (first occurrence)
      # Issue is "recurrence" if it was closed and is now open again
      is_truly_new = issue.count <= 1
      is_recurrence = issue.closed_at.present? && issue.status == "open"

      return unless is_truly_new || is_recurrence || first_in_deploy
    end

    # Get rate limit from UI preference (per-fingerprint)
    rate_limit_minutes = frequency_to_minutes(pref&.frequency)

    # For first_in_deploy mode: include release_id in key so each deploy gets ONE notification
    # For other modes: just use fingerprint-based dedup
    rate_limit_key = if first_in_deploy && latest_release
      "issue_rate_limit:#{issue.project_id}:new_issue:deploy_#{latest_release.id}:#{issue.fingerprint}"
    else
      fingerprint_rate_limit_key(issue, "new_issue")
    end

    # ATOMIC check-and-set to prevent race conditions
    # SET with NX returns true only if key was set (didn't exist)
    # This prevents multiple concurrent jobs from all sending alerts
    ttl = first_in_deploy ? 7.days.to_i : rate_limit_minutes.minutes.to_i
    lock_acquired = self.class.with_redis { |redis| redis.set(rate_limit_key, true, ex: ttl, nx: true) }
    return unless lock_acquired

    # Send alerts (only one job wins the race)
    project.alert_rules.active.for_type("new_issue").each do |rule|
      AlertJob.perform_async(rule.id, "new_issue", {
        issue_id: issue.id,
        fingerprint: issue.fingerprint,
        first_in_deploy: first_in_deploy
      })
    end
  end

  # Convert UI frequency setting to minutes
  # This makes the rate limit PER-FINGERPRINT based on user's choice
  def frequency_to_minutes(frequency)
    case frequency
    when "immediate"
      MIN_RATE_LIMIT_MINUTES  # Still enforce minimum 5 min to prevent spam
    when "every_30_minutes"
      30
    when "every_2_hours"
      120
    when "first_in_deploy", "after_close"
      MIN_RATE_LIMIT_MINUTES  # These modes use special logic, not time-based
    else
      30  # Default: 30 minutes (AppSignal Action Interval default)
    end
  end

  def fingerprint_rate_limit_key(issue, alert_type)
    "issue_rate_limit:#{issue.project_id}:#{alert_type}:#{issue.fingerprint}"
  end
end
