class AccountSlackNotificationService
  include Rails.application.routes.url_helpers

  def initialize(account)
    @account = account
    @webhook_url = account.slack_webhook_url
  end

  def configured?
    @webhook_url.present?
  end

  def send_error_frequency_alert(issue, payload, user: nil)
    return unless configured?

    # Check user preferences
    return unless should_notify_user?(user, 'error_notifications')

    message = build_error_frequency_message(issue, payload, user)
    send_notification(message, user)
  end

  def send_performance_alert(event, payload, user: nil)
    return unless configured?

    # Check user preferences
    return unless should_notify_user?(user, 'performance_notifications')

    message = build_performance_message(event, payload, user)
    send_notification(message, user)
  end

  def send_n_plus_one_alert(payload, user: nil)
    return unless configured?

    # Check user preferences
    return unless should_notify_user?(user, 'n_plus_one_notifications')

    message = build_n_plus_one_message(payload, user)
    send_notification(message, user)
  end

  def send_new_issue_alert(issue, user: nil)
    return unless configured?

    # Check user preferences
    return unless should_notify_user?(user, 'new_issue_notifications')

    message = build_new_issue_message(issue, user)
    send_notification(message, user)
  end

  def send_custom_alert(title, message, color: 'warning', user: nil)
    return unless configured?

    notification = build_custom_message(title, message, color, user)
    send_notification(notification, user)
  end

  # Send notifications to all users in the account based on their preferences
  def broadcast_to_account(alert_type, &block)
    return unless configured?

    @account.users.each do |user|
      next unless should_notify_user?(user, alert_type)

      yield(user) if block_given?
    end
  end

  private

  def send_notification(message, user = nil)
    channel = determine_channel(user)

    notifier = Slack::Notifier.new(@webhook_url) do
      defaults channel: channel,
               username: 'ActiveRabbit',
               icon_emoji: ':rabbit:'
    end

    notifier.post(message)
  rescue StandardError => e
    Rails.logger.error "Failed to send account Slack notification: #{e.message}"
    raise e
  end

  def determine_channel(user)
    if user
      preferences = @account.user_notification_preferences(user)
      personal_channel = preferences['personal_channel']
      return personal_channel if personal_channel.present?
    end

    @account.slack_channel
  end

  def should_notify_user?(user, notification_type)
    return true unless user # For system-wide notifications

    return false unless @account.slack_notifications_enabled?

    preferences = @account.user_notification_preferences(user)
    preferences[notification_type] == true
  end

  def account_url
    if Rails.env.development?
      'http://localhost:3000/account/settings'
    else
      "#{ENV.fetch('APP_HOST', 'https://activerabbit.com')}/account/settings"
    end
  end

  def project_url(project)
    if Rails.env.development?
      "http://localhost:3000/projects/#{project.slug}"
    else
      "#{ENV.fetch('APP_HOST', 'https://activerabbit.com')}/projects/#{project.slug}"
    end
  end

  def build_error_frequency_message(issue, payload, user)
    user_mention = user ? "<@#{user.email}> " : ''

    {
      text: "#{user_mention}🚨 *High Error Frequency Alert*",
      attachments: [
        {
          color: 'danger',
          fallback: "High error frequency detected for #{issue.title}",
          fields: [
            {
              title: 'Account',
              value: @account.name,
              short: true
            },
            {
              title: 'Project',
              value: issue.project.name,
              short: true
            },
            {
              title: 'Environment',
              value: issue.project.environment,
              short: true
            },
            {
              title: 'Issue',
              value: issue.title.truncate(100),
              short: false
            },
            {
              title: 'Frequency',
              value: "#{payload['count']} occurrences in #{payload['time_window']} minutes",
              short: true
            },
            {
              title: 'Exception Type',
              value: issue.exception_type,
              short: true
            },
            {
              title: 'Location',
              value: issue.controller_action || issue.request_path || 'Unknown',
              short: false
            }
          ],
          actions: [
            {
              type: 'button',
              text: 'View Issue',
              url: "#{project_url(issue.project)}/errors/#{issue.id}",
              style: 'primary'
            },
            {
              type: 'button',
              text: 'Account Settings',
              url: account_url,
              style: 'default'
            }
          ],
          footer: 'ActiveRabbit Account Notifications',
          footer_icon: 'https://activerabbit.com/icon.png',
          ts: Time.current.to_i
        }
      ]
    }
  end

  def build_performance_message(event, payload, user)
    user_mention = user ? "<@#{user.email}> " : ''

    {
      text: "#{user_mention}⚠️ *Performance Alert*",
      attachments: [
        {
          color: 'warning',
          fallback: "Slow response time detected: #{payload['duration_ms']}ms",
          fields: [
            {
              title: 'Account',
              value: @account.name,
              short: true
            },
            {
              title: 'Project',
              value: event.project.name,
              short: true
            },
            {
              title: 'Environment',
              value: event.project.environment,
              short: true
            },
            {
              title: 'Response Time',
              value: "#{payload['duration_ms']}ms",
              short: true
            },
            {
              title: 'Threshold',
              value: 'Expected < 2000ms',
              short: true
            },
            {
              title: 'Endpoint',
              value: payload['controller_action'] || 'Unknown',
              short: false
            },
            {
              title: 'Occurred At',
              value: event.occurred_at.strftime('%Y-%m-%d %H:%M:%S UTC'),
              short: true
            }
          ],
          actions: [
            {
              type: 'button',
              text: 'View Performance',
              url: "#{project_url(event.project)}/performance",
              style: 'primary'
            }
          ],
          footer: 'ActiveRabbit Account Notifications',
          footer_icon: 'https://activerabbit.com/icon.png',
          ts: Time.current.to_i
        }
      ]
    }
  end

  def build_n_plus_one_message(payload, user)
    user_mention = user ? "<@#{user.email}> " : ''
    incidents = payload['incidents']
    controller_action = payload['controller_action']

    query_summary = incidents.first(3).map do |incident|
      "• #{incident['count_in_request']}x #{incident['sql_fingerprint']['query_type']} queries"
    end.join("\n")

    {
      text: "#{user_mention}🔍 *N+1 Query Alert*",
      attachments: [
        {
          color: 'warning',
          fallback: "N+1 queries detected in #{controller_action}",
          fields: [
            {
              title: 'Account',
              value: @account.name,
              short: true
            },
            {
              title: 'Controller/Action',
              value: controller_action,
              short: false
            },
            {
              title: 'High Severity Incidents',
              value: incidents.size.to_s,
              short: true
            },
            {
              title: 'Impact',
              value: 'Database performance degradation',
              short: true
            },
            {
              title: 'Query Summary',
              value: query_summary,
              short: false
            }
          ],
          footer: 'ActiveRabbit Account Notifications',
          footer_icon: 'https://activerabbit.com/icon.png',
          ts: Time.current.to_i
        }
      ]
    }
  end

  def build_new_issue_message(issue, user)
    user_mention = user ? "<@#{user.email}> " : ''

    {
      text: "#{user_mention}🆕 *New Issue Detected*",
      attachments: [
        {
          color: 'danger',
          fallback: "New issue detected: #{issue.exception_type}",
          fields: [
            {
              title: 'Account',
              value: @account.name,
              short: true
            },
            {
              title: 'Project',
              value: issue.project.name,
              short: true
            },
            {
              title: 'Environment',
              value: issue.project.environment,
              short: true
            },
            {
              title: 'Exception Type',
              value: issue.exception_type,
              short: true
            },
            {
              title: 'Status',
              value: issue.status.humanize,
              short: true
            },
            {
              title: 'Error Message',
              value: issue.message.truncate(200),
              short: false
            },
            {
              title: 'Location',
              value: issue.controller_action || issue.request_path || 'Unknown',
              short: false
            },
            {
              title: 'First Seen',
              value: issue.first_seen_at.strftime('%Y-%m-%d %H:%M:%S UTC'),
              short: true
            }
          ],
          actions: [
            {
              type: 'button',
              text: 'Investigate Issue',
              url: "#{project_url(issue.project)}/errors/#{issue.id}",
              style: 'danger'
            },
            {
              type: 'button',
              text: 'Mark as WIP',
              url: "#{project_url(issue.project)}/errors/#{issue.id}/edit",
              style: 'primary'
            }
          ],
          footer: 'ActiveRabbit Account Notifications',
          footer_icon: 'https://activerabbit.com/icon.png',
          ts: Time.current.to_i
        }
      ]
    }
  end

  def build_custom_message(title, message, color, user)
    user_mention = user ? "<@#{user.email}> " : ''

    {
      text: "#{user_mention}#{title}",
      attachments: [
        {
          color: color,
          fallback: "#{title}: #{message}",
          fields: [
            {
              title: 'Account',
              value: @account.name,
              short: true
            },
            {
              title: 'Message',
              value: message,
              short: false
            }
          ],
          footer: 'ActiveRabbit Account Notifications',
          footer_icon: 'https://activerabbit.com/icon.png',
          ts: Time.current.to_i
        }
      ]
    }
  end
end
