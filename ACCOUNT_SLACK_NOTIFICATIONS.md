# 🏢 Account-Level Slack Notifications for ActiveRabbit

## 🎯 Overview

ActiveRabbit now supports **account-level Slack notifications** that allow each user in an account to receive personalized notifications based on their preferences. This is perfect for teams and organizations where:

- Multiple users share the same Slack workspace
- Each user wants different notification preferences
- Users want personal channels or DMs for alerts
- Account-wide webhook management is preferred

## ✨ Key Features

### 🔧 **Account-Level Configuration**
- **Single webhook URL** per account (shared across all users)
- **Environment variable support** for secure webhook storage
- **Default channel** for account-wide notifications
- **Master enable/disable** switch for all notifications

### 👤 **Personal User Preferences**
- **Individual notification types** (errors, performance, N+1, new issues)
- **Personal Slack channels** (override account default)
- **User-specific mentions** in notifications
- **Granular control** over what each user receives

### 🔄 **Smart Notification Flow**
```
Alert Triggered → Account Configured? → User Preferences → Personal Channel → Slack
                     ↓ No
                 Project Configured? → Project Channel → Slack
                     ↓ No
                 Email Notification
```

## 🚀 Implementation Details

### Database Schema
```ruby
# accounts table now has:
settings: json # Stores webhook_url, channel, user preferences

# Example account settings:
{
  "slack_webhook_url" => "https://hooks.slack.com/services/...",
  "slack_channel" => "#alerts",
  "slack_notifications_enabled" => true,
  "user_preferences" => {
    "123" => {  # user_id
      "error_notifications" => true,
      "performance_notifications" => false,
      "personal_channel" => "#john-alerts"
    }
  }
}
```

### New Services & Controllers

**AccountSlackNotificationService**
- Handles account-level Slack messaging
- User preference checking
- Personal channel routing
- Broadcast to multiple users

**AccountSettingsController**
- Account-wide Slack configuration
- User preference management
- Test notifications

### Enhanced Alert Flow
```ruby
# In AlertJob
def send_error_frequency_alert(alert_rule, payload, notification)
  # 1. Try account-level notification first
  if send_account_slack_notification(account, :error_frequency, issue, payload)
    # Success - sent to users based on their preferences
  # 2. Fall back to project-level
  elsif project.slack_configured?
    # Send to project channel
  # 3. Final fallback to email
  else
    send_email_alert(...)
  end
end
```

## 🎛️ User Experience

### Account Admin Setup
1. **Go to Dashboard** → Click "Slack Settings"
2. **Configure webhook URL** (or use environment variable)
3. **Set default channel** (e.g., `#alerts`)
4. **Enable notifications** for the account
5. **Test the integration**

### Individual User Preferences
1. **Personal notification types**: Choose which alerts to receive
2. **Personal channel**: Override account default (optional)
3. **Immediate effect**: Changes apply to future notifications

### Notification Examples

**Error Alert to Personal Channel:**
```
@john.doe 🚨 High Error Frequency Alert

Account: Acme Corp
Project: E-commerce API
Issue: ArgumentError in UsersController#show
Frequency: 15 occurrences in 5 minutes

[View Issue] [Account Settings]
```

**Performance Alert to Team Channel:**
```
@jane.smith ⚠️ Performance Alert

Account: Acme Corp
Project: E-commerce API
Response Time: 2,500ms
Endpoint: ProductsController#index

[View Performance]
```

## 🔒 Security Features

### Environment Variable Priority
```bash
# Account-specific (highest priority)
SLACK_WEBHOOK_URL_ACME_CORP="https://hooks.slack.com/..."

# Global fallback
SLACK_WEBHOOK_URL="https://hooks.slack.com/..."

# Database setting (lowest priority)
```

### Parameter Filtering
```ruby
# Webhook URLs automatically filtered from logs
Rails.application.config.filter_parameters += [
  :slack_webhook_url, :webhook_url, :slack_webhook
]
```

## 🧪 Testing

### Via Web Interface
```
Account Settings → Test Notification
```

### Via Docker Rails Console
```bash
docker-compose run --rm web bin/rails console

# Test account notifications
account = Account.first
service = AccountSlackNotificationService.new(account)
service.send_custom_alert("Test", "Account notification test")

# Test user preferences
user = account.users.first
prefs = account.user_notification_preferences(user)
account.update_user_notification_preferences(user, {
  'error_notifications' => true,
  'personal_channel' => '#my-alerts'
})
```

### Test Script
```ruby
# Updated test script handles account-level notifications
./script/test_slack_integration.rb
```

## 📋 Migration from Project-Level

### Automatic Fallback
- **Existing project configurations** still work
- **Account-level takes priority** when configured
- **No breaking changes** to existing setups

### Migration Path
1. **Set up account-level webhook** (same URL as project)
2. **Configure user preferences**
3. **Test notifications**
4. **Remove project-level webhooks** (optional)

## 🔧 Configuration Options

### Account Settings
```ruby
account = Account.find(1)

# Webhook configuration
account.slack_webhook_url = "https://hooks.slack.com/..."
account.slack_channel = "#alerts"
account.enable_slack_notifications!

# Check configuration
account.slack_configured?           # => true
account.slack_notifications_enabled? # => true
account.slack_webhook_from_env?     # => false (if stored in DB)
```

### User Preferences
```ruby
# Get user preferences
preferences = account.user_notification_preferences(user)
# => {
#   'error_notifications' => true,
#   'performance_notifications' => true,
#   'n_plus_one_notifications' => true,
#   'new_issue_notifications' => true,
#   'personal_channel' => nil
# }

# Update preferences
account.update_user_notification_preferences(user, {
  'error_notifications' => false,
  'personal_channel' => '#john-alerts'
})
```

## 🚀 Production Deployment with Docker

### Environment Variables
```bash
# docker-compose.yml or deployment config
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...

# Account-specific (optional)
SLACK_WEBHOOK_URL_ACME_CORP=https://hooks.slack.com/services/...
```

### Database Migration
```bash
# Run migration to add settings column to accounts
docker-compose run --rm web bin/rails db:migrate
```

### Health Check
```bash
# Verify Slack integration
docker-compose run --rm web bin/rails runner "
  account = Account.first
  puts 'Account Slack configured: ' + account.slack_configured?.to_s
  puts 'Users in account: ' + account.users.count.to_s
"
```

## 📊 Benefits

### For Teams
- **Centralized configuration** - One webhook URL per account
- **Individual control** - Each user sets their preferences
- **Reduced noise** - Users only get relevant notifications
- **Personal channels** - Direct messages or personal channels

### For Administrators
- **Easy management** - Configure once at account level
- **Security** - Environment variables for production
- **Audit trail** - See who receives what notifications
- **Flexibility** - Mix of account and project notifications

### For Developers
- **Clean architecture** - Account → Users → Preferences
- **Backward compatible** - Existing project settings still work
- **Extensible** - Easy to add new notification types
- **Testable** - Comprehensive test coverage

## 🔗 Routes

```ruby
# Account settings
GET    /account/settings                    # Show account Slack settings
PATCH  /account/settings                    # Update account settings
POST   /account/settings/test_notification  # Test account notification
PATCH  /account/settings/update_user_preferences # Update user preferences

# Project settings (still available)
GET    /projects/:id/settings               # Show project settings
PATCH  /projects/:id/settings               # Update project settings
```

## 🎉 Summary

The account-level Slack notification system provides a **perfect balance** between:
- **Team collaboration** (shared webhook, account-wide settings)
- **Individual preferences** (personal channels, notification types)
- **Security** (environment variables, parameter filtering)
- **Flexibility** (account-level + project-level + email fallbacks)

This implementation makes ActiveRabbit notifications **more personal, more secure, and more scalable** for teams of any size! 🚀
