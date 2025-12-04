class AlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 3

  def perform(alert_rule_id, alert_type, payload)
    alert_rule = nil
    project = nil
    issue = nil

    ActsAsTenant.without_tenant do
      alert_rule = AlertRule.find(alert_rule_id)
      project = alert_rule.project
      issue = Issue.find(payload["issue_id"]) if payload["issue_id"]
    end

    ActsAsTenant.with_tenant(project.account) do
      notification = AlertNotification.create!(
        alert_rule: alert_rule,
        project: project,
        account_id: project.account.id,
        notification_type: determine_notification_type(project),
        payload: payload,
        status: "pending"
      )

      begin
        case alert_type
        when "error_frequency"
          send_error_frequency_alert(project, issue, payload, notification)
        when "performance_regression"
          send_performance_alert(project, payload, notification)
        when "n_plus_one"
          send_n_plus_one_alert(project, payload, notification)
        when "new_issue"
          send_new_issue_alert(project, payload, notification)
        else
          raise "Unknown alert type: #{alert_type}"
        end

        notification.mark_sent!
        Rails.logger.info "Alert sent successfully: #{alert_type} for project #{project.slug}"

      rescue => e
        notification.mark_failed!(e.message)
        Rails.logger.error "Failed to send alert: #{e.message}"
        raise e
      end
    end
  end

  private

  def determine_notification_type(project)
    project.slack_access_token.present? ? "slack" : "email"
  end

  # ------------------------
  # Slack sending methods
  # ------------------------
  def slack_service(project)
    SlackNotificationService.new(project)
  end

  def send_error_frequency_alert(project, issue, payload, notification)
    if notification.notification_type == "slack" && slack_service(project).configured?
      slack_service(project).send_error_frequency_alert(issue, payload)
    else
      send_email_alert(project, "Error Frequency Alert", build_error_frequency_email(issue, payload))
    end
  end

  def send_performance_alert(project, payload, notification)
    event = ActsAsTenant.without_tenant { PerformanceEvent.unscoped.find_by(id: payload["event_id"]) }
    return unless event

    if notification.notification_type == "slack" && slack_service(project).configured?
      slack_service(project).send_performance_alert(event, payload)
    else
      send_email_alert(project, "Performance Alert", build_performance_email(event, payload))
    end
  end

  def send_n_plus_one_alert(project, payload, notification)
    if notification.notification_type == "slack" && slack_service(project).configured?
      slack_service(project).send_n_plus_one_alert(payload)
    else
      send_email_alert(project, "N+1 Query Alert", build_n_plus_one_email(payload))
    end
  end

  def send_new_issue_alert(project, payload, notification)
    issue = ActsAsTenant.without_tenant { Issue.find(payload["issue_id"]) }

    if notification.notification_type == "slack" && slack_service(project).configured?
      slack_service(project).send_new_issue_alert(issue)
    else
      send_email_alert(project, "New Issue Alert", build_new_issue_email(issue))
    end
  end

  # ------------------------
  # Email fallback
  # ------------------------
  def send_email_alert(project, subject, body)
    AlertMailer.send_alert(
      to: project.user.email,
      subject: "[#{project.name}] #{subject}",
      body: body,
      project: project
    ).deliver_now
  end

  # ------------------------
  # Slack message builders (reuse старые методы)
  # ------------------------
  def build_error_frequency_email(issue, payload)
    <<~EMAIL
      High error frequency detected for issue: #{issue.title}
      Project: #{issue.project.name}
      Frequency: #{payload['count']} occurrences in #{payload['time_window']} minutes
      Controller/Action: #{issue.controller_action || 'Unknown'}
    EMAIL
  end

  def build_performance_email(event, payload)
    <<~EMAIL
      Performance alert for project #{event.project.name}
      Response Time: #{payload['duration_ms']}ms
      Endpoint: #{payload['controller_action'] || 'Unknown'}
      Environment: #{event.environment}
    EMAIL
  end

  def build_n_plus_one_email(payload)
    incidents = payload["incidents"]
    controller_action = payload["controller_action"]

    <<~EMAIL
      N+1 query detected in #{controller_action}
      High Severity Incidents: #{incidents.size}
      Queries:
      #{incidents.map { |i| "- #{i['count_in_request']}x #{i['sql_fingerprint']['normalized_query']}" }.join("\n")}
    EMAIL
  end

  def build_new_issue_email(issue)
    <<~EMAIL
      New issue in project #{issue.project.name}
      Exception: #{issue.exception_class}
      Message: #{issue.sample_message}
      Location: #{issue.controller_action || issue.top_frame || 'Unknown'}
    EMAIL
  end
end
