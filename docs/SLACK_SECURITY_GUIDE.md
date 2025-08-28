# 🔐 Slack Webhook Security Guide

This guide covers security best practices for storing and managing Slack webhook URLs in ActiveRabbit.

## 🎯 Storage Options

ActiveRabbit supports **two methods** for storing Slack webhook URLs, allowing you to choose based on your security requirements:

### 1. 🌍 Environment Variables (Recommended for Production)

**Most Secure Option** - Store webhook URLs as environment variables:

```bash
# Global webhook for all projects
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"

# Project-specific webhook (higher priority)
export SLACK_WEBHOOK_URL_MYAPP_PRODUCTION="https://hooks.slack.com/services/T11111111/B11111111/YYYYYYYYYYYYYYYYYYYYYYYY"
```

**Advantages:**
- ✅ Never stored in database
- ✅ Not visible in application logs
- ✅ Can't be extracted from database backups
- ✅ Follows 12-factor app principles
- ✅ Easy to rotate without code changes
- ✅ Works with container orchestration (Docker, Kubernetes)

### 2. 💾 Database Storage (Convenient for Development)

**Convenient Option** - Store webhook URLs in the project settings:

```ruby
project.slack_webhook_url = "https://hooks.slack.com/services/..."
```

**Advantages:**
- ✅ Per-project configuration via UI
- ✅ Easy to manage for multiple projects
- ✅ No server configuration required
- ✅ Good for development and testing

**Considerations:**
- ⚠️ Stored in database (encrypted at rest recommended)
- ⚠️ Visible to users with database access
- ⚠️ Included in database backups

## 🔒 Security Implementation

### Parameter Filtering
Webhook URLs are automatically filtered from Rails logs:

```ruby
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += [
  :slack_webhook_url, :webhook_url, :slack_webhook
]
```

### Environment Variable Priority
The system checks for webhooks in this order:

1. `SLACK_WEBHOOK_URL_#{PROJECT_SLUG}` (project-specific)
2. `SLACK_WEBHOOK_URL` (global fallback)
3. Database setting (if no env vars found)

### Automatic Detection
The UI automatically detects and displays when environment variables are used:

```ruby
project.slack_webhook_from_env? # => true if using env vars
```

## 🚀 Production Deployment

### Docker/Container Setup

```dockerfile
# Dockerfile
ENV SLACK_WEBHOOK_URL=""

# At runtime
docker run -e SLACK_WEBHOOK_URL="https://hooks.slack.com/..." myapp
```

### Kamal Deployment

```yaml
# config/deploy.yml
env:
  secret:
    - RAILS_MASTER_KEY
    - SLACK_WEBHOOK_URL
```

```bash
# .kamal/secrets
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
```

### Kubernetes Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: slack-webhook
type: Opaque
stringData:
  webhook-url: "https://hooks.slack.com/services/..."
```

```yaml
# deployment.yaml
env:
- name: SLACK_WEBHOOK_URL
  valueFrom:
    secretKeyRef:
      name: slack-webhook
      key: webhook-url
```

### Heroku

```bash
heroku config:set SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
```

## 🛡️ Security Best Practices

### 1. Webhook URL Rotation
Regularly rotate webhook URLs:

```bash
# Update environment variable
export SLACK_WEBHOOK_URL="new_webhook_url"

# Or update in your deployment system
# No application restart required
```

### 2. Access Control
Limit who can view/modify webhook settings:

```ruby
# In your authorization system
def can_manage_slack_settings?
  current_user.admin? || current_user.project_owner?(project)
end
```

### 3. Audit Logging
Track webhook configuration changes:

```ruby
# Add to your audit log system
def log_webhook_change(project, old_value, new_value)
  AuditLog.create!(
    action: 'slack_webhook_updated',
    project: project,
    user: current_user,
    details: {
      old_configured: old_value.present?,
      new_configured: new_value.present?,
      changed_at: Time.current
    }
  )
end
```

### 4. Network Security
Restrict outbound connections if possible:

```bash
# Allow only Slack webhook endpoints
iptables -A OUTPUT -d hooks.slack.com -p tcp --dport 443 -j ACCEPT
```

## 🧪 Testing Security

### 1. Verify Parameter Filtering

```ruby
# Test that webhooks don't appear in logs
Rails.logger.info("Webhook: #{project.slack_webhook_url}")
# Should show: Webhook: [FILTERED]
```

### 2. Test Environment Variable Priority

```bash
# Set env var
export SLACK_WEBHOOK_URL_TEST="env_webhook"

# Set database value
project.update(settings: { slack_webhook_url: "db_webhook" })

# Should return env_webhook
project.slack_webhook_url
```

### 3. Validate Access Controls

```ruby
# Test unauthorized access
unauthorized_user = create(:user)
expect {
  unauthorized_user.update_project_slack_settings(project)
}.to raise_error(Authorization::NotAuthorized)
```

## 🚨 Incident Response

### Webhook Compromise
If a webhook URL is compromised:

1. **Immediate Actions:**
   ```bash
   # Revoke the webhook in Slack
   # Update environment variable
   export SLACK_WEBHOOK_URL="new_secure_webhook"

   # Clear database value if used
   project.update(settings: project.settings.except('slack_webhook_url'))
   ```

2. **Verification:**
   ```ruby
   # Verify new webhook works
   SlackNotificationService.new(project).send_custom_alert(
     "🔒 Security Update",
     "Webhook URL has been rotated"
   )
   ```

3. **Audit:**
   - Review access logs
   - Check for unauthorized notifications
   - Update security procedures

## 📊 Monitoring

### Webhook Health Monitoring

```ruby
# Monitor webhook success rates
class SlackWebhookMonitor
  def self.check_health(project)
    begin
      service = SlackNotificationService.new(project)
      service.send_custom_alert("🏥 Health Check", "System operational")

      # Log success
      Rails.logger.info "Slack webhook healthy for project #{project.slug}"
      true
    rescue => e
      # Log failure and alert
      Rails.logger.error "Slack webhook failed for project #{project.slug}: #{e.message}"
      false
    end
  end
end
```

### Metrics to Track

- Webhook success/failure rates
- Configuration change frequency
- Environment vs database usage
- Failed authentication attempts

## 🤝 Team Guidelines

### Development
- Use database storage for local development
- Never commit real webhook URLs to version control
- Use placeholder URLs in seeds/fixtures

### Staging
- Use environment variables
- Test with separate Slack channels
- Validate security configurations

### Production
- **Always** use environment variables
- Enable audit logging
- Monitor webhook health
- Regular security reviews

## 📚 Resources

- [Slack Webhook Security](https://api.slack.com/messaging/webhooks#security)
- [12-Factor App Config](https://12factor.net/config)
- [OWASP Secrets Management](https://owasp.org/www-community/vulnerabilities/Improper_Secret_Management)
- [Rails Security Guide](https://guides.rubyonrails.org/security.html)
