# ✅ Ready to Deploy - ActiveRabbit

## Your Configuration Summary

### 🖥️ Server Details
- **Hetzner Server**: YOUR_SERVER_IP (configure in deploy.yml)
- **Database**: Ubicloud PostgreSQL (configure in .kamal/secrets)
- **Background Jobs**: Redis + Sidekiq (no Solid Queue)

### 📋 What's Configured

✅ **Database**: PostgreSQL on Ubicloud
✅ **Caching**: Redis (not solid_cache_store)
✅ **Jobs**: Sidekiq (not solid_queue)
✅ **Deployment**: Kamal with Docker
✅ **Server IP**: Configure in `config/deploy.yml`
✅ **Rails Secrets**: Master key and SECRET_KEY_BASE (configure in .kamal/secrets)

## 🚀 Deploy Commands

### 1. First, complete your secrets configuration:

Edit `.kamal/secrets` and update these placeholders:

```bash
# You still need to set:
KAMAL_REGISTRY_PASSWORD=your-docker-hub-access-token

# Optional (only if using these features):
STRIPE_SECRET_KEY=sk_live_your_stripe_secret_key
STRIPE_SIGNING_SECRET=whsec_your_webhook_secret
SMTP_PASSWORD=your-smtp-password
```

### 2. Update Docker registry in `config/deploy.yml`:

```yaml
registry:
  username: your-docker-hub-username  # Replace this
```

### 3. Deploy!

```bash
# First time setup (installs Docker on server)
bin/kamal setup

# Deploy your application
bin/kamal deploy

# Run database migrations
bin/kamal app exec "bin/rails db:migrate"
```

## 🌐 Access Your App

- **URL**: http://YOUR_SERVER_IP
- **Sidekiq Dashboard**: http://YOUR_SERVER_IP/sidekiq

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Hetzner       │    │   Ubicloud       │    │   Your App      │
│  YOUR_SERVER_IP │    │   PostgreSQL     │    │   (Local Dev)   │
│                 │    │                  │    │                 │
│ ┌─────────────┐ │    │ ┌──────────────┐ │    │ ┌─────────────┐ │
│ │ Rails App   │ │◄──►│ │  Database    │ │    │ │   Kamal     │ │
│ │ (Docker)    │ │    │ │              │ │    │ │  Deploy     │ │
│ └─────────────┘ │    │ └──────────────┘ │    │ └─────────────┘ │
│                 │    │                  │    │                 │
│ ┌─────────────┐ │    └──────────────────┘    └─────────────────┘
│ │ Sidekiq     │ │
│ │ (Docker)    │ │
│ └─────────────┘ │
│                 │
│ ┌─────────────┐ │
│ │ Redis       │ │
│ │ (Docker)    │ │
│ └─────────────┘ │
└─────────────────┘
```

## Next Steps After Deploy

1. **Test the app** at http://YOUR_SERVER_IP
2. **Check Sidekiq** is processing jobs
3. **Set up a domain** (optional) for SSL
4. **Configure monitoring** and alerts
5. **Set up automated backups**

## Useful Commands

```bash
# Check app status
bin/kamal app details

# View logs
bin/kamal logs

# Rails console
bin/kamal console

# Restart services
bin/kamal app restart
bin/kamal accessory restart redis

# Update environment variables
bin/kamal env push
```

You're all set! 🎉
