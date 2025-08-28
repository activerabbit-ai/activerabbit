# Production Environment Variables for ActiveRabbit

Copy these to your `.env` file or set them in your production environment:

```bash
# Application
RAILS_ENV=production
SECRET_KEY_BASE=your-secret-key-base-here
APP_HOST=your-domain.com

# Database
DATABASE_URL=postgresql://username:password@host:port/database_name

# Redis (for Sidekiq and caching)
REDIS_URL=redis://localhost:6379/0

# Stripe (for billing)
STRIPE_PUBLIC_KEY=pk_live_your_stripe_public_key
STRIPE_SECRET_KEY=sk_live_your_stripe_secret_key
STRIPE_SIGNING_SECRET=whsec_your_webhook_secret

# Email Configuration
MAILER_FROM_EMAIL=noreply@your-domain.com
ALERT_FROM_EMAIL=alerts@your-domain.com
SMTP_HOST=smtp.your-provider.com
SMTP_PORT=587
SMTP_USERNAME=your-smtp-username
SMTP_PASSWORD=your-smtp-password

# GitHub Integration (optional)
GITHUB_TOKEN=ghp_your_github_token

# Monitoring & Logging
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true

# Security
FORCE_SSL=true

# Sidekiq Web UI Protection
SIDEKIQ_USERNAME=admin
SIDEKIQ_PASSWORD=your-secure-password

# Rate Limiting
RACK_ATTACK_ENABLED=true

# Performance
WEB_CONCURRENCY=2
RAILS_MAX_THREADS=5
```

## Required Environment Variables

### Essential
- `SECRET_KEY_BASE` - Generate with `rails secret`
- `DATABASE_URL` - PostgreSQL connection string
- `REDIS_URL` - Redis connection for Sidekiq and caching

### Email Alerts
- `MAILER_FROM_EMAIL` - Default sender email
- `ALERT_FROM_EMAIL` - Email for alerts
- SMTP settings for email delivery

### Stripe Billing
- `STRIPE_PUBLIC_KEY` and `STRIPE_SECRET_KEY` - Stripe API keys
- `STRIPE_SIGNING_SECRET` - For webhook verification

### Optional
- `GITHUB_TOKEN` - For creating N+1 query fix PRs
- `APP_HOST` - Your domain for email links
- Sidekiq credentials for web UI protection
