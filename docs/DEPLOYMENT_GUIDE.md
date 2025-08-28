# ActiveRabbit Deployment Guide
## Hetzner + Ubicloud PostgreSQL + Kamal

This guide walks you through deploying ActiveRabbit to Hetzner Cloud using Docker and Kamal, with Ubicloud PostgreSQL as the database.

## Prerequisites

### 1. Hetzner Cloud Server
- Create a Hetzner Cloud server (recommend CX21 or higher)
- Note the public IP address
- Ensure Docker is installed on the server

### 2. Ubicloud PostgreSQL Database
- Create a PostgreSQL instance on Ubicloud
- Note the connection details (host, port, username, password)
- Create a database named `activerabbit_production`

### 3. Domain Name (Optional but Recommended)
- Point your domain to your Hetzner server IP
- Configure DNS A record

## Setup Steps

### Step 1: Configure Your Server IP
Edit `config/deploy.yml` and replace `YOUR_HETZNER_SERVER_IP` with your actual server IP:

```yaml
servers:
  web:
    - 1.2.3.4  # Your Hetzner server IP
  job:
    hosts:
      - 1.2.3.4  # Your Hetzner server IP
```

### Step 2: Configure Secrets
1. Copy the secrets template:
   ```bash
   cp .kamal/secrets.example .kamal/secrets
   ```

2. Fill in your actual values in `.kamal/secrets`:
   - `RAILS_MASTER_KEY`: Get from `config/master.key`
   - `SECRET_KEY_BASE`: Generate with `rails secret`
   - `DATABASE_URL`: Your Ubicloud PostgreSQL connection string
   - `REDIS_URL`: Will be `redis://YOUR_HETZNER_IP:6379/0`
   - Docker registry credentials
   - Stripe keys (if using billing)
   - SMTP credentials (for emails)

### Step 3: Configure Domain and SSL (Optional)
Edit `config/deploy.yml` to set your domain:

```yaml
proxy:
  ssl: true
  host: your-domain.com  # Replace with your domain
```

If you don't have a domain, comment out the proxy section and access via IP.

### Step 4: Configure Docker Registry
Update the registry section in `config/deploy.yml`:

```yaml
registry:
  username: your-docker-username
  password:
    - KAMAL_REGISTRY_PASSWORD
```

For Docker Hub, use your Docker Hub username and access token.

## Deployment Commands

### Initial Setup (First Time Only)
```bash
# Install Kamal if not already done
bundle install

# Setup the server (installs Docker, creates directories)
bin/kamal setup
```

### Deploy Application
```bash
# Deploy the application
bin/kamal deploy
```

### Useful Kamal Commands
```bash
# Check application status
bin/kamal app details

# View application logs
bin/kamal logs

# Access Rails console on production
bin/kamal console

# Access server shell
bin/kamal shell

# Restart the application
bin/kamal app restart

# Update environment variables
bin/kamal env push

# Rollback to previous version
bin/kamal rollback
```

## Database Setup

After first deployment, you'll need to run database migrations:

```bash
# Run database migrations
bin/kamal app exec "bin/rails db:migrate"

# Optionally seed the database
bin/kamal app exec "bin/rails db:seed"
```

## Environment Variables Reference

### Required Secrets (in `.kamal/secrets`)
- `RAILS_MASTER_KEY` - Rails master key for credentials
- `SECRET_KEY_BASE` - Rails secret key base
- `DATABASE_URL` - Ubicloud PostgreSQL connection string
- `REDIS_URL` - Redis connection for Sidekiq
- `KAMAL_REGISTRY_PASSWORD` - Docker registry password

### Optional Secrets (if using features)
- `STRIPE_SECRET_KEY` - Stripe secret key for billing
- `STRIPE_SIGNING_SECRET` - Stripe webhook signing secret
- `SMTP_PASSWORD` - SMTP password for emails

### Public Environment Variables (in `config/deploy.yml`)
- `STRIPE_PUBLIC_KEY` - Stripe public key
- `MAILER_FROM_EMAIL` - Default sender email
- `ALERT_FROM_EMAIL` - Alert sender email
- SMTP configuration (host, port, username)

## Monitoring and Maintenance

### Health Checks
Your app will be available at:
- With domain: `https://your-domain.com`
- Without domain: `http://YOUR_HETZNER_IP`

### Log Monitoring
```bash
# Follow application logs
bin/kamal logs -f

# Check specific service logs
bin/kamal logs -f web
bin/kamal logs -f job
```

### Sidekiq Monitoring
Access Sidekiq web interface at `/sidekiq` (requires authentication).

## Troubleshooting

### Common Issues

1. **Database Connection Issues**
   - Verify DATABASE_URL in secrets
   - Check Ubicloud firewall allows connections from Hetzner IP
   - Ensure database exists and user has proper permissions

2. **Redis Connection Issues**
   - Check Redis accessory is running: `bin/kamal accessory details redis`
   - Restart Redis if needed: `bin/kamal accessory restart redis`

3. **SSL Certificate Issues**
   - Ensure domain points to server IP
   - Check Let's Encrypt rate limits
   - Verify port 80 and 443 are open

4. **Application Won't Start**
   - Check logs: `bin/kamal logs`
   - Verify all required secrets are set
   - Check if migrations need to be run

### Getting Help
- Check application logs: `bin/kamal logs`
- Access Rails console: `bin/kamal console`
- SSH into server: `bin/kamal shell`

## Security Considerations

1. **Firewall Configuration**
   - Only allow necessary ports (22, 80, 443)
   - Restrict SSH access to your IP

2. **Database Security**
   - Use strong passwords
   - Enable SSL for database connections
   - Restrict database access to your server IP

3. **Application Security**
   - Keep Rails and gems updated
   - Use strong secret keys
   - Enable FORCE_SSL in production

## Backup Strategy

1. **Database Backups**
   - Configure automated backups in Ubicloud
   - Test restore procedures

2. **Application Data**
   - Backup uploaded files if using Active Storage
   - Consider backing up Redis data for job queues

## Cost Optimization

- Use appropriate Hetzner server size for your traffic
- Monitor Ubicloud database usage
- Consider Redis memory limits
- Use CDN for static assets if needed
