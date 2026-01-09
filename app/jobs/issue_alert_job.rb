class IssueAlertJob
  include Sidekiq::Job
  sidekiq_options queue: :alerts, retry: 2

  REDIS = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/1")

  # Minimum rate limit (5 minutes) to prevent spam even if user sets "immediate"
  MIN_RATE_LIMIT_MINUTES = 5

  def perform(issue_id, tenant_id)
    ActsAsTenant.with_tenant(Account.find(tenant_id)) do
      issue = Issue.find(issue_id)
      project = issue.project

      # Check if this is first occurrence after a deploy (first_in_deploy mode)
      first_in_deploy = first_occurrence_in_deploy?(issue, project)

      # Check error frequency rules (with per-fingerprint rate limiting from UI preference)
      check_error_frequency_with_rate_limit(issue, project)

      # New issue alerts (with per-fingerprint dedup using UI preference)
      handle_new_issue_alert(issue, project, first_in_deploy)
    end
  end

  private

  # Check if this error is the first occurrence since the latest deploy
  # AND we haven't already notified for this fingerprint in this deploy
  def first_occurrence_in_deploy?(issue, project)
    latest_release = project.releases.recent.first
    return false unless latest_release&.deployed_at

    is_new_in_deploy = false

    # First occurrence if issue was created after the deploy
    if issue.first_seen_at && issue.first_seen_at >= latest_release.deployed_at
      is_new_in_deploy = true
    end

    # Recurrence: issue was closed before deploy and is now reopening
    if issue.closed_at && issue.closed_at < latest_release.deployed_at
      is_new_in_deploy = true
    end

    return false unless is_new_in_deploy

    # Check if we already notified for this fingerprint in THIS deploy
    # This ensures we only send ONE "first in deploy" notification per fingerprint per deploy
    deploy_key = "first_in_deploy:#{project.id}:#{latest_release.id}:#{issue.fingerprint}"
    !REDIS.exists?(deploy_key)
  end

  # Mark that we've notified for this fingerprint in this deploy
  def mark_notified_for_deploy(issue, project)
    latest_release = project.releases.recent.first
    return unless latest_release

    deploy_key = "first_in_deploy:#{project.id}:#{latest_release.id}:#{issue.fingerprint}"
    # Set for 7 days (longer than any deploy cycle)
    REDIS.set(deploy_key, true, ex: 7.days.to_i)
  end

  # Error frequency rules with per-fingerprint rate limiting
  def check_error_frequency_with_rate_limit(issue, project)
    pref = project.notification_pref_for("error_frequency")
    rate_limit_minutes = frequency_to_minutes(pref&.frequency)

    AlertRule.check_error_frequency_rules(issue, rate_limit_minutes: rate_limit_minutes)
  end

  # Handle new issue alerts with per-fingerprint dedup
  # Rate limit is based on user's UI preference
  def handle_new_issue_alert(issue, project, first_in_deploy)
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
    rate_limit_key = fingerprint_rate_limit_key(issue, "new_issue")

    # ATOMIC check-and-set to prevent race conditions
    # SET with NX returns true only if key was set (didn't exist)
    # This prevents multiple concurrent jobs from all sending alerts
    lock_acquired = REDIS.set(rate_limit_key, true, ex: rate_limit_minutes.minutes.to_i, nx: true)
    return unless lock_acquired

    # Send alerts (only one job wins the race)
    project.alert_rules.active.for_type("new_issue").each do |rule|
      AlertJob.perform_async(rule.id, "new_issue", {
        issue_id: issue.id,
        fingerprint: issue.fingerprint,
        first_in_deploy: first_in_deploy
      })
    end

    # Mark as notified for this deploy (for first_in_deploy mode)
    mark_notified_for_deploy(issue, project) if first_in_deploy
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
