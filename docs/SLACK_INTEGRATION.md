# 🔔 Slack Integration for ActiveRabbit

ActiveRabbit now supports real-time Slack notifications for error tracking, performance monitoring, and system alerts. This integration uses the [slack-notifier](https://github.com/slack-notifier/slack-notifier) gem to deliver rich, actionable notifications directly to your Slack workspace.

## 🚀 Features

- **Rich Notifications**: Beautiful, formatted messages with project context, error details, and action buttons
- **Multiple Alert Types**: Error frequency, performance issues, N+1 queries, and new issue detection
- **Configurable Channels**: Send notifications to specific channels or direct messages
- **Test Notifications**: Built-in testing to verify your integration is working
- **Automatic Fallbacks**: Graceful degradation to email notifications when Slack is unavailable

## 📋 Setup Instructions

### 1. Create a Slack App

1. Go to [Slack Apps](https://api.slack.com/apps)
2. Click "Create New App" → "From scratch"
3. Name your app (e.g., "ActiveRabbit Alerts")
4. Select your workspace

### 2. Enable Incoming Webhooks

1. In your app settings, go to "Incoming Webhooks"
2. Turn on "Activate Incoming Webhooks"
3. Click "Add New Webhook to Workspace"
4. Select the channel where you want notifications
5. Copy the webhook URL (starts with `https://hooks.slack.com/services/...`)

### 3. Configure in ActiveRabbit

1. Go to your project in ActiveRabbit
2. Click the "Settings" button
3. In the Slack Integration section:
   - Paste your webhook URL
   - Set your preferred channel (e.g., `#alerts`)
   - Enable notifications
4. Click "Save & Test" to verify the integration

## 🎯 Notification Types

### Error Frequency Alerts
Triggered when error rates exceed configured thresholds:
```
🚨 High Error Frequency Alert
Project: MyApp Production
Issue: ArgumentError in UsersController#show
Frequency: 15 occurrences in 5 minutes
```

### Performance Alerts
Sent when response times are slower than expected:
```
⚠️ Performance Alert
Project: MyApp Production
Response Time: 2,500ms
Endpoint: UsersController#index
```

### N+1 Query Detection
Alerts for database performance issues:
```
🔍 N+1 Query Alert
Controller/Action: PostsController#index
High Severity Incidents: 3
Queries: 15x SELECT, 8x UPDATE
```

### New Issue Detection
Immediate alerts for new error types:
```
🆕 New Issue Detected
Project: MyApp Production
Exception: NoMethodError
Message: undefined method `name' for nil:NilClass
```

## ⚙️ Configuration Options

### Project Settings
Each project can have independent Slack configuration:

```ruby
# Check if Slack is configured
project.slack_configured?

# Get/set webhook URL
project.slack_webhook_url = "https://hooks.slack.com/services/..."

# Get/set channel
project.slack_channel = "#alerts"

# Enable/disable notifications
project.enable_slack_notifications!
project.disable_slack_notifications!
```

### Alert Rules
Configure when notifications are sent:

- **Error Frequency**: Threshold and time window for error rates
- **Performance**: Response time thresholds
- **N+1 Queries**: Database query optimization alerts
- **New Issues**: Immediate notification for new error types

## 🧪 Testing

### Via Web Interface
1. Go to Project Settings
2. Configure your Slack webhook
3. Click "Test Notification"

### Via Command Line
```bash
# Run the test script
./script/test_slack_integration.rb
```

### Programmatically
```ruby
# Send a custom test notification
slack_service = SlackNotificationService.new(project)
slack_service.send_custom_alert(
  "🧪 Test Alert",
  "This is a test message",
  color: 'good'
)
```

## 🔧 Advanced Usage

### Custom Notifications
```ruby
# Send custom alerts from your application code
slack_service = SlackNotificationService.new(project)
slack_service.send_custom_alert(
  "🚀 Deployment Complete",
  "Version 1.2.3 deployed successfully to production",
  color: 'good'
)
```

### Multiple Channels
Configure different channels for different alert types by customizing the `SlackNotificationService`:

```ruby
# In your project settings
{
  "slack_webhook_url" => "https://hooks.slack.com/services/...",
  "slack_error_channel" => "#errors",
  "slack_performance_channel" => "#performance",
  "slack_general_channel" => "#alerts"
}
```

## 🛠️ Troubleshooting

### Common Issues

**"Slack webhook URL not configured"**
- Ensure you've set the webhook URL in project settings
- Verify the URL starts with `https://hooks.slack.com/services/`

**"Failed to send notification"**
- Check your internet connection
- Verify the webhook URL is correct and active
- Ensure the Slack app has permissions to post to the channel

**"Test notification not received"**
- Check the configured channel exists
- Verify the bot has access to post in that channel
- Look for notifications in your Slack app's direct message

### Debug Mode
Enable debug logging to troubleshoot issues:

```ruby
# In Rails console
Rails.logger.level = :debug

# Test a notification
SlackNotificationService.new(project).send_custom_alert("Test", "Debug message")
```

## 📊 Integration Architecture

```
Rails App Error
    ↓
AlertJob (Sidekiq)
    ↓
SlackNotificationService
    ↓
slack-notifier gem
    ↓
Slack Webhook API
    ↓
Your Slack Channel
```

## 🔒 Security Notes

- Webhook URLs contain sensitive tokens - store them securely
- Use environment variables for production webhook URLs
- Regularly rotate webhook URLs if compromised
- Monitor webhook usage in your Slack app settings

## 📈 Best Practices

1. **Channel Organization**: Use dedicated channels for different alert types
2. **Alert Fatigue**: Configure reasonable thresholds to avoid spam
3. **Testing**: Regularly test your integration after changes
4. **Monitoring**: Track notification delivery success rates
5. **Fallbacks**: Always configure email as a backup notification method

## 🤝 Contributing

To extend the Slack integration:

1. Add new notification types in `SlackNotificationService`
2. Create corresponding alert rules in `AlertRule`
3. Update the UI in `project_settings/show.html.erb`
4. Add tests for new functionality

## 📚 Resources

- [Slack API Documentation](https://api.slack.com/)
- [slack-notifier Gem](https://github.com/slack-notifier/slack-notifier)
- [Incoming Webhooks Guide](https://api.slack.com/messaging/webhooks)
