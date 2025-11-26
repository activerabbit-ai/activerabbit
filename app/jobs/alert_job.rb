class AlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 3

  def perform(alert_rule_id, alert_type, payload)
    # Find alert_rule and project without tenant
    alert_rule = nil
    project = nil
    ActsAsTenant.without_tenant do
      alert_rule = AlertRule.find(alert_rule_id)
      project = alert_rule.project
    end
    issue = nil
    if payload["issue_id"]
      ActsAsTenant.without_tenant do
        issue = Issue.find(payload["issue_id"])
      end
    end

    ActsAsTenant.with_tenant(project.account) do
      # Create notification record
      notification = AlertNotification.create!(
        alert_rule: alert_rule,
        project: project,
        account_id: project.account.id,
        notification_type: determine_notification_type(alert_rule),
        payload: payload,
        status: "pending"
      )

      begin
        case alert_type
        when "error_frequency"
          send_error_frequency_alert(alert_rule, issue, payload, notification)
        when "performance_regression"
          send_performance_alert(alert_rule, payload, notification)
        when "n_plus_one"
          send_n_plus_one_alert(alert_rule, payload, notification)
        when "new_issue"
          send_new_issue_alert(alert_rule, payload, notification)
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

  def determine_notification_type(alert_rule)
    # Priority: Account Slack > Project Slack > Email
    if alert_rule.project.account.slack_configured? || alert_rule.project.settings["slack_webhook_url"].present?
      "slack"
    else
      "email"
    end
  end

  # Send account-level Slack notification to all users based on their preferences
  def send_account_slack_notification(account, alert_type, *args)
    return false unless account.slack_configured? && account.slack_notifications_enabled?

    account_service = AccountSlackNotificationService.new(account)

    case alert_type
    when :error_frequency
      issue, payload = args
      account_service.broadcast_to_account("error_notifications") do |user|
        account_service.send_error_frequency_alert(issue, payload, user: user)
      end
    when :performance
      event, payload = args
      account_service.broadcast_to_account("performance_notifications") do |user|
        account_service.send_performance_alert(event, payload, user: user)
      end
    when :n_plus_one
      payload = args.first
      account_service.broadcast_to_account("n_plus_one_notifications") do |user|
        account_service.send_n_plus_one_alert(payload, user: user)
      end
    when :new_issue
      issue = args.first
      account_service.broadcast_to_account("new_issue_notifications") do |user|
        account_service.send_new_issue_alert(issue, user: user)
      end
    else
      return false
    end

    true
  rescue StandardError => e
    Rails.logger.error "Account Slack notification failed: #{e.message}"
    false
  end

  def send_error_frequency_alert(alert_rule, issue, payload, notification)
    ActsAsTenant.with_tenant(alert_rule.project.account) do
      if notification.notification_type == "slack"
        if send_account_slack_notification(alert_rule.project.account, :error_frequency, issue, payload)
          Rails.logger.info "Sent account-level error frequency alert for issue #{issue.id}"
        elsif alert_rule.project.slack_configured?
          slack_service = SlackNotificationService.new(alert_rule.project)
          slack_service.send_error_frequency_alert(issue, payload)
          Rails.logger.info "Sent project-level error frequency alert for issue #{issue.id}"
        else
          Rails.logger.warn "No Slack configuration found for project #{alert_rule.project.id}, sending email"
          send_email_alert(alert_rule, "Error Frequency Alert", build_error_frequency_email(issue, payload))
        end
      else
        send_email_alert(alert_rule, "Error Frequency Alert", build_error_frequency_email(issue, payload))
      end
    end
  end

  def send_performance_alert(alert_rule, payload, notification)
    event = Event.find(payload["event_id"])

    if notification.notification_type == "slack"
      # Try account-level notification first, then fall back to project-level test
      if send_account_slack_notification(alert_rule.project.account, :performance, event, payload)
        Rails.logger.info "Sent account-level performance alert for event #{event.id}"
      elsif alert_rule.project.slack_configured?
        slack_service = SlackNotificationService.new(alert_rule.project)
        slack_service.send_performance_alert(event, payload)
        Rails.logger.info "Sent project-level performance alert for event #{event.id}"
      else
        Rails.logger.warn "No Slack configuration found for project #{alert_rule.project.id}"
        send_email_alert(alert_rule, "Performance Alert", build_performance_email(event, payload))
      end
    else
      send_email_alert(alert_rule, "Performance Alert", build_performance_email(event, payload))
    end
  end

  def send_n_plus_one_alert(alert_rule, payload, notification)
    if notification.notification_type == "slack"
      # Try account-level notification first, then fall back to project-level
      if send_account_slack_notification(alert_rule.project.account, :n_plus_one, payload)
        Rails.logger.info "Sent account-level N+1 alert for #{payload['controller_action']}"
      elsif alert_rule.project.slack_configured?
        slack_service = SlackNotificationService.new(alert_rule.project)
        slack_service.send_n_plus_one_alert(payload)
        Rails.logger.info "Sent project-level N+1 alert for #{payload['controller_action']}"
      else
        Rails.logger.warn "No Slack configuration found for project #{alert_rule.project.id}"
        send_email_alert(alert_rule, "N+1 Query Alert", build_n_plus_one_email(payload))
      end
    else
      send_email_alert(alert_rule, "N+1 Query Alert", build_n_plus_one_email(payload))
    end
  end

  def send_new_issue_alert(alert_rule, payload, notification)
    issue = nil
    ActsAsTenant.without_tenant do
      issue = Issue.find(payload["issue_id"])
    end

    ActsAsTenant.with_tenant(alert_rule.project.account) do
      if notification.notification_type == "slack"
        # Try account-level notification first, then fall back to project-level
        if send_account_slack_notification(alert_rule.project.account, :new_issue, issue)
          Rails.logger.info "Sent account-level new issue alert for issue #{issue.id}"
        elsif alert_rule.project.slack_configured?
          slack_service = SlackNotificationService.new(alert_rule.project)
          slack_service.send_new_issue_alert(issue)
          Rails.logger.info "Sent project-level new issue alert for issue #{issue.id}"
        else
          Rails.logger.warn "No Slack configuration found for project #{alert_rule.project.id}, sending email"
          send_email_alert(alert_rule, "New Issue Alert", build_new_issue_email(issue))
        end
      else
        send_email_alert(alert_rule, "New Issue Alert", build_new_issue_email(issue))
      end
    end
  end

  def send_slack_alert(alert_rule, message)
    # This method is deprecated - individual alert methods now call SlackNotificationService directly
    # Keeping for backward compatibility
    slack_service = SlackNotificationService.new(alert_rule.project)

    unless slack_service.configured?
      raise "Slack webhook URL not configured"
    end

    # Fallback to custom alert for any legacy message format
    slack_service.send_custom_alert(
      message[:text] || "Alert",
      message[:fallback] || "Alert triggered"
    )
  end

  def send_email_alert(alert_rule, subject, body)
    # This would integrate with your email service (ActionMailer, SendGrid, etc.)
    AlertMailer.send_alert(
      to: alert_rule.project.user.email,
      subject: "[#{alert_rule.project.name}] #{subject}",
      body: body,
      project: alert_rule.project
    ).deliver_now
  end

  def build_error_frequency_slack_message(issue, payload)
    {
      text: "🚨 High Error Frequency Alert",
      attachments: [
        {
          color: "danger",
          fields: [
            {
              title: "Project",
              value: issue.project.name,
              short: true
            },
            {
              title: "Issue",
              value: issue.title,
              short: true
            },
            {
              title: "Frequency",
              value: "#{payload['count']} occurrences in #{payload['time_window']} minutes",
              short: true
            },
            {
              title: "Controller/Action",
              value: issue.controller_action || "Unknown",
              short: true
            }
          ],
          footer: "ActiveRabbit",
          ts: Time.current.to_i
        }
      ]
    }
  end

  def build_performance_slack_message(event, payload)
    {
      text: "⚠️ Performance Alert",
      attachments: [
        {
          color: "warning",
          fields: [
            {
              title: "Project",
              value: event.project.name,
              short: true
            },
            {
              title: "Response Time",
              value: "#{payload['duration_ms']}ms",
              short: true
            },
            {
              title: "Endpoint",
              value: payload["controller_action"] || "Unknown",
              short: true
            },
            {
              title: "Environment",
              value: event.environment,
              short: true
            }
          ],
          footer: "ActiveRabbit",
          ts: Time.current.to_i
        }
      ]
    }
  end

  def build_n_plus_one_slack_message(payload)
    incidents = payload["incidents"]
    controller_action = payload["controller_action"]

    {
      text: "🔍 N+1 Query Alert",
      attachments: [
        {
          color: "warning",
          fields: [
            {
              title: "Controller/Action",
              value: controller_action,
              short: true
            },
            {
              title: "High Severity Incidents",
              value: incidents.size.to_s,
              short: true
            },
            {
              title: "Queries",
              value: incidents.map { |i| "#{i['count_in_request']}x #{i['sql_fingerprint']['query_type']}" }.join(", "),
              short: false
            }
          ],
          footer: "ActiveRabbit",
          ts: Time.current.to_i
        }
      ]
    }
  end

  def build_new_issue_slack_message(issue)
    {
      text: "🆕 New Issue Detected",
      attachments: [
        {
          color: "danger",
          fields: [
            {
              title: "Project",
              value: issue.project.name,
              short: true
            },
            {
              title: "Exception",
              value: issue.exception_class,
              short: true
            },
            {
              title: "Message",
              value: issue.message.truncate(200),
              short: false
            },
            {
              title: "Location",
              value: issue.controller_action || issue.request_path || "Unknown",
              short: true
            }
          ],
          footer: "ActiveRabbit",
          ts: Time.current.to_i
        }
      ]
    }
  end

  def build_error_frequency_email(issue, payload)
    <<~EMAIL
      High error frequency detected for issue: #{issue.title}

      Project: #{issue.project.name}
      Frequency: #{payload['count']} occurrences in #{payload['time_window']} minutes
      Controller/Action: #{issue.controller_action || 'Unknown'}

      Issue Details:
      - Exception Type: #{issue.exception_class}
      - Message: #{issue.sample_message}
      - First Seen: #{issue.first_seen_at}
      - Last Seen: #{issue.last_seen_at}
      - Total Count: #{issue.count}

      Please investigate this issue as soon as possible.
    EMAIL
  end

  def build_performance_email(event, payload)
    <<~EMAIL
      Performance alert triggered for slow response time.

      Project: #{event.project.name}
      Response Time: #{payload['duration_ms']}ms
      Endpoint: #{payload['controller_action'] || 'Unknown'}
      Environment: #{event.environment}
      Occurred At: #{event.occurred_at}

      Please review the performance of this endpoint.
    EMAIL
  end

  def build_n_plus_one_email(payload)
    incidents = payload["incidents"]
    controller_action = payload["controller_action"]

    <<~EMAIL
      N+1 query alert detected.

      Controller/Action: #{controller_action}
      High Severity Incidents: #{incidents.size}

      Detected Queries:
      #{incidents.map { |i| "- #{i['count_in_request']}x #{i['sql_fingerprint']['normalized_query'].truncate(100)}" }.join("\n")}

      Please review and optimize these database queries to improve performance.
    EMAIL
  end

  def build_new_issue_email(issue)
    <<~EMAIL
      New issue detected in your application.

      Project: #{issue.project.name}
      Exception: #{issue.exception_class}
      Message: #{issue.message}
      Location: #{issue.controller_action || issue.request_path || 'Unknown'}
      First Seen: #{issue.first_seen_at}

      Please investigate this new error.
    EMAIL
  end
end
