# Quick Deploy to Hetzner Guide

## Your Server Details
- **Server**: active-rabbit-ubuntu-4gb
- **IP**: 5.78.134.55
- **Reverse DNS**: static.55.134.78.5.clients.your-server.de

## Pre-Deployment Checklist

### 1. Configure Secrets
Edit `.kamal/secrets` with your actual values:

```bash
# Required - Get from your Rails app
RAILS_MASTER_KEY=your-rails-master-key-from-config/master.key
SECRET_KEY_BASE=generate-with-rails-secret

# Required - Your Ubicloud PostgreSQL details
DATABASE_URL=postgresql://username:password@ubicloud-host:5432/activerabbit_production
ACTIVERABBIT_DATABASE_PASSWORD=your-ubicloud-db-password

# Required - Docker Hub credentials
KAMAL_REGISTRY_PASSWORD=your-docker-hub-access-token

# Optional - Only if using Stripe billing
STRIPE_SECRET_KEY=sk_live_your_stripe_secret_key
STRIPE_SIGNING_SECRET=whsec_your_webhook_secret

# Optional - Only if sending emails
SMTP_PASSWORD=your-smtp-password
```

### 2. Configure Docker Registry
Update `config/deploy.yml` with your Docker Hub username:

```yaml
registry:
  username: your-docker-hub-username  # Replace this
```

### 3. Configure Domain (Optional)
If you have a domain, update `config/deploy.yml`:

```yaml
proxy:
  ssl: true
  host: yourdomain.com  # Replace or comment out to use IP
```

If no domain, comment out the entire `proxy:` section to access via IP.

## Deploy Commands

### First Time Setup
```bash
# Make sure you're in the project directory
cd /Users/alex/GPT/activeagent/activerabbit

# Install dependencies if needed
bundle install

# Setup the server (installs Docker, creates directories)
bin/kamal setup
```

### Deploy Application
```bash
# Deploy your application
bin/kamal deploy
```

### After First Deploy - Database Setup
```bash
# Run database migrations
bin/kamal app exec "bin/rails db:migrate"

# Create an admin user (optional)
bin/kamal app exec "bin/rails console"
# Then in console: User.create!(email: 'admin@example.com', password: 'password')
```

## Access Your Application

- **Without Domain**: http://5.78.134.55
- **With Domain**: https://yourdomain.com (if configured)
- **Sidekiq Dashboard**: http://5.78.134.55/sidekiq

## Useful Commands

```bash
# Check app status
bin/kamal app details

# View logs
bin/kamal logs

# Restart app
bin/kamal app restart

# Access Rails console
bin/kamal console

# SSH into server
bin/kamal shell

# Check Redis status
bin/kamal accessory details redis
```

## Troubleshooting

### Can't Connect to Server
```bash
# Test SSH connection
ssh root@5.78.134.55
```

### Database Issues
```bash
# Check database connectivity from server
bin/kamal app exec "bin/rails runner 'puts ActiveRecord::Base.connection.execute(\"SELECT 1\").first'"
```

### Redis Issues
```bash
# Restart Redis
bin/kamal accessory restart redis

# Check Redis logs
bin/kamal accessory logs redis
```

## Next Steps After Deployment

1. **Test the application** at http://5.78.134.55
2. **Configure your domain** (if you have one)
3. **Set up monitoring** and alerts
4. **Configure backups** for your database
5. **Set up SSL certificate** (automatic with domain)

## Security Notes

- Your server is accessible at 5.78.134.55
- Kamal will automatically configure firewall rules
- Use strong passwords for all services
- Consider setting up SSH key authentication
