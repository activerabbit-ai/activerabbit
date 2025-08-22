class AlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 3

  def perform(alert_rule_id, alert_type, payload)
    alert_rule = AlertRule.find(alert_rule_id)
    project = alert_rule.project

    # Create notification record
    notification = AlertNotification.create!(
      alert_rule: alert_rule,
      project: project,
      notification_type: determine_notification_type(alert_rule),
      payload: payload,
      status: 'pending'
    )

    begin
      case alert_type
      when 'error_frequency'
        send_error_frequency_alert(alert_rule, payload, notification)
      when 'performance_regression'
        send_performance_alert(alert_rule, payload, notification)
      when 'n_plus_one'
        send_n_plus_one_alert(alert_rule, payload, notification)
      when 'new_issue'
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

  private

  def determine_notification_type(alert_rule)
    # For now, prioritize Slack if configured, otherwise email
    if alert_rule.project.settings['slack_webhook_url'].present?
      'slack'
    else
      'email'
    end
  end

  def send_error_frequency_alert(alert_rule, payload, notification)
    issue = Issue.find(payload['issue_id'])

    if notification.notification_type == 'slack'
      send_slack_alert(alert_rule, build_error_frequency_slack_message(issue, payload))
    else
      send_email_alert(alert_rule, 'Error Frequency Alert', build_error_frequency_email(issue, payload))
    end
  end

  def send_performance_alert(alert_rule, payload, notification)
    event = Event.find(payload['event_id'])

    if notification.notification_type == 'slack'
      send_slack_alert(alert_rule, build_performance_slack_message(event, payload))
    else
      send_email_alert(alert_rule, 'Performance Alert', build_performance_email(event, payload))
    end
  end

  def send_n_plus_one_alert(alert_rule, payload, notification)
    if notification.notification_type == 'slack'
      send_slack_alert(alert_rule, build_n_plus_one_slack_message(payload))
    else
      send_email_alert(alert_rule, 'N+1 Query Alert', build_n_plus_one_email(payload))
    end
  end

  def send_new_issue_alert(alert_rule, payload, notification)
    issue = Issue.find(payload['issue_id'])

    if notification.notification_type == 'slack'
      send_slack_alert(alert_rule, build_new_issue_slack_message(issue))
    else
      send_email_alert(alert_rule, 'New Issue Alert', build_new_issue_email(issue))
    end
  end

  def send_slack_alert(alert_rule, message)
    webhook_url = alert_rule.project.settings['slack_webhook_url']
    raise 'Slack webhook URL not configured' unless webhook_url.present?

    response = Faraday.post(webhook_url) do |req|
      req.headers['Content-Type'] = 'application/json'
      req.body = message.to_json
    end

    unless response.success?
      raise "Slack webhook failed with status #{response.status}: #{response.body}"
    end
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
              value: issue.controller_action || 'Unknown',
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
              value: payload['controller_action'] || 'Unknown',
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
    incidents = payload['incidents']
    controller_action = payload['controller_action']

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
              value: issue.exception_type,
              short: true
            },
            {
              title: "Message",
              value: issue.message.truncate(200),
              short: false
            },
            {
              title: "Location",
              value: issue.controller_action || issue.request_path || 'Unknown',
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
      - Exception Type: #{issue.exception_type}
      - Message: #{issue.message}
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
    incidents = payload['incidents']
    controller_action = payload['controller_action']

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
      Exception: #{issue.exception_type}
      Message: #{issue.message}
      Location: #{issue.controller_action || issue.request_path || 'Unknown'}
      First Seen: #{issue.first_seen_at}

      Please investigate this new error.
    EMAIL
  end
end
