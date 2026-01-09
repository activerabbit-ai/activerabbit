class AlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 3
  URL_HOST = ENV.fetch("APP_HOST", "localhost:3000")
  URL_PROTOCOL = Rails.env.production? ? "https" : "http"

  # Alert types that use per-fingerprint rate limiting (handled in IssueAlertJob)
  # These should NOT use global rate limiting here
  PER_FINGERPRINT_ALERT_TYPES = %w[new_issue error_frequency].freeze

  def perform(alert_rule_id, alert_type, payload)
    alert_rule = nil
    project = nil
    issue = nil

    ActsAsTenant.without_tenant do
      alert_rule = AlertRule.find(alert_rule_id)
      project = alert_rule.project
      issue = Issue.find(payload["issue_id"]) if payload["issue_id"]
    end

    return unless project.notifications_enabled?

    preference = project.notification_pref_for(alert_type)
    return unless preference&.enabled

    ActsAsTenant.with_tenant(project.account) do
      # For error alerts: per-fingerprint rate limiting is handled in IssueAlertJob
      # Skip global rate limiting to allow different fingerprints through
      #
      # For other alerts (performance, n+1): use global rate limiting
      unless PER_FINGERPRINT_ALERT_TYPES.include?(alert_type)
        preference.with_lock do
          return unless preference.can_send_now?
          preference.mark_sent!
        end
      end

      notification = AlertNotification.create!(
        alert_rule: alert_rule,
        project: project,
        notification_type: "multi",
        account_id: project.account.id,
        payload: payload,
        status: "pending"
      )

      begin
        dispatch_alert(alert_type, project, issue, payload)

        notification.mark_sent!
        Rails.logger.info "Alert sent: #{alert_type} for project #{project.slug}"

      rescue => e
        notification.mark_failed!(e.message)
        Rails.logger.error "Alert failed: #{e.message}"
        raise e
      end
    end
  end

  private

  def dispatch_alert(alert_type, project, issue, payload)
    case alert_type
    when "error_frequency"
      deliver_error_frequency(project, issue, payload)
    when "performance_regression"
      deliver_performance(project, payload)
    when "n_plus_one"
      deliver_n_plus_one(project, payload)
    when "new_issue"
      deliver_new_issue(project, payload)
    else
      raise "Unknown alert type: #{alert_type}"
    end
  end

  def deliver_error_frequency(project, issue, payload)
    if project.notify_via_slack?
      slack_service(project).send_error_frequency_alert(issue, payload)
    end

    if project.notify_via_email?
      send_email_alert(
        project,
        "Error Frequency Alert",
        build_error_frequency_email(issue, payload),
        dashboard_url: project_error_url(project, issue)
      )
    end
  end

  def deliver_performance(project, payload)
    event = ActsAsTenant.without_tenant do
      PerformanceEvent.unscoped.find_by(id: payload["event_id"])
    end
    return unless event

    slack_service(project).send_performance_alert(event, payload) if project.notify_via_slack?

    send_email_alert(
      project,
      "Performance Alert",
      build_performance_email(event, payload),
      dashboard_url: project_performance_issue_url(project, event)
    ) if project.notify_via_email?
  end

  def deliver_n_plus_one(project, payload)
    slack_service(project).send_n_plus_one_alert(payload) if project.notify_via_slack?

    send_email_alert(
      project,
      "N+1 Query Alert",
      build_n_plus_one_email(payload)
    ) if project.notify_via_email?
  end

  def deliver_new_issue(project, payload)
    issue = ActsAsTenant.without_tenant { Issue.find(payload["issue_id"]) }

    slack_service(project).send_new_issue_alert(issue) if project.notify_via_slack?

    send_email_alert(
      project,
      "New Issue Alert",
      build_new_issue_email(issue),
      dashboard_url: project_error_url(project, issue)
    ) if project.notify_via_email?
  end

  # ------------------------
  # Slack sending methods
  # ------------------------
  def slack_service(project)
    SlackNotificationService.new(project)
  end

  # ------------------------
  # Email fallback
  # ------------------------
  def send_email_alert(project, subject, body, dashboard_url: nil)
    project.account.users.find_each.with_index do |user, index|
      # Small delay between emails to avoid Resend rate limit (2/second)
      sleep(0.6) if index > 0

      AlertMailer.send_alert(
        to: user.email,
        subject: "#{project.name}: #{subject}",
        body: body,
        project: project,
        dashboard_url: dashboard_url
      ).deliver_now
    end
  end

  def project_error_url(project, issue)
    Rails.application.routes.url_helpers.project_error_url(project, issue, host: URL_HOST, protocol: URL_PROTOCOL)
  end

  def project_performance_issue_url(project, event)
    Rails.application.routes.url_helpers.project_performance_issue_url(project, event, host: URL_HOST, protocol: URL_PROTOCOL)
  end

  # ------------------------
  # Slack message builders (reuse старые методы)
  # ------------------------
  def build_error_frequency_email(issue, payload)
    <<~EMAIL
      🚨 HIGH ERROR FREQUENCY
      Project:
        #{issue.project.name}

      Issue:
        #{issue.title}

      Frequency:
        #{payload['count']} occurrences in #{payload['time_window']} minutes

      Controller/Action:
        #{issue.controller_action || 'Unknown'}
    EMAIL
  end

  def build_performance_email(event, payload)
    duration = payload["duration_ms"]
    endpoint = event.target.presence || "Unknown"

    <<~EMAIL
      PERFORMANCE ALERT

      Project:
        #{event.project.name}

      Details:
        • Response time: #{duration} ms
        • Endpoint: #{endpoint}
        • Environment: #{event.environment}

      Recommendation:
        Check database queries, external APIs, and recent deploys.
    EMAIL
  end

  def build_n_plus_one_email(payload)
    incidents = payload["incidents"]
    controller_action = payload["controller_action"]

    <<~EMAIL
      🚨 N+1 QUERY DETECTED
      Location:
        #{controller_action}

      Impact:
        #{incidents.size} repeating query patterns detected

      Queries:
        #{incidents.map { |i| "- #{i['count_in_request']}x #{i['sql_fingerprint']['normalized_query']}" }.join("\n")}
    EMAIL
  end

  def build_new_issue_email(issue)
    <<~EMAIL
      🚨 APPLICATION ERROR

      Project:
        #{issue.project.name}

      Error:
        #{issue.exception_class}
        #{issue.sample_message}

      Location:
        #{error_location(issue)}

      Recommendation:
        Review the stack trace and recent changes around this code.
    EMAIL
  end

  def error_location(issue)
    issue.controller_action ||
      issue.error_location ||
      issue.top_frame ||
      "Unknown"
  end
end
