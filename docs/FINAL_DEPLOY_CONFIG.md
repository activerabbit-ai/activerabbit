# 🎯 Final Deployment Configuration - ActiveRabbit

## ✅ Complete Setup Summary

### 🖥️ Infrastructure
- **Hetzner Server**: `YOUR_SERVER_IP` (configure in deploy.yml)
- **Database**: Ubicloud PostgreSQL (configure in .kamal/secrets)
- **Background Jobs**: Redis + Sidekiq (no Solid Queue)
- **Deployment**: Kamal + Docker

### 🗄️ Database Configuration
**Ubicloud PostgreSQL** - Configure in `.kamal/secrets`:

```bash
DATABASE_URL=postgresql://postgres:YOUR_PASSWORD@your-postgres-host.ubicloud.com:5432/postgres

# Individual parameters (for tools that need them):
PGHOST=your-postgres-host.ubicloud.com
PGPORT=5432
PGUSER=postgres
PGPASSWORD=YOUR_PASSWORD
PGDATABASE=postgres
```

**⚠️ IMPORTANT**: Never commit actual credentials to version control. Store them securely in `.kamal/secrets` which is gitignored.

### 🔧 What's Ready

✅ **Rails Secrets**: Master key and SECRET_KEY_BASE configured
✅ **Database**: Full Ubicloud PostgreSQL connection
✅ **Caching**: Redis (no solid_cache_store)
✅ **Jobs**: Sidekiq (no solid_queue)
✅ **Server**: Hetzner IP configured
✅ **Docker**: Production Dockerfile ready

## 🚀 Deploy Now!

### Step 1: Complete Docker Registry Setup

Edit `.kamal/secrets` and add your Docker Hub token:
```bash
KAMAL_REGISTRY_PASSWORD=your-docker-hub-access-token
```

Edit `config/deploy.yml` and add your Docker Hub username:
```yaml
registry:
  username: your-docker-hub-username
```

### Step 2: Deploy Commands

```bash
# First time setup (installs Docker on your Hetzner server)
bin/kamal setup

# Deploy your application
bin/kamal deploy

# Run database migrations on your Ubicloud PostgreSQL
bin/kamal app exec "bin/rails db:migrate"

# Optional: Create initial data
bin/kamal app exec "bin/rails db:seed"
```

### Step 3: Verify Deployment

```bash
# Check app status
bin/kamal app details

# Check logs
bin/kamal logs

# Test database connection
bin/kamal app exec "bin/rails runner 'puts ActiveRecord::Base.connection.execute(\"SELECT version()\").first'"
```

## 🌐 Access Your Application

- **Main App**: http://YOUR_SERVER_IP
- **Sidekiq Dashboard**: http://YOUR_SERVER_IP/sidekiq

## 🏗️ Architecture Overview

```
┌─────────────────────────────────┐    ┌──────────────────────────────┐
│        Hetzner Cloud            │    │        Ubicloud              │
│        YOUR_SERVER_IP           │    │                              │
│                                 │    │                              │
│  ┌─────────────────────────────┐│    │  ┌─────────────────────────┐ │
│  │      Rails Web App          ││◄──►│  │     PostgreSQL          │ │
│  │      (Docker Container)     ││    │  │     Database            │ │
│  │                             ││    │  │                         │ │
│  │  • Serves HTTP requests     ││    │  │  Host: your-postgres-   │ │
│  │  • Handles user sessions    ││    │  │    host.ubicloud.com    │ │
│  │  • Processes web traffic    ││    │  │  Port: 5432             │ │
│  └─────────────────────────────┘│    │  │  User: postgres         │ │
│                                 │    │  │  DB: postgres           │ │
│  ┌─────────────────────────────┐│    │  └─────────────────────────┘ │
│  │    Sidekiq Job Workers      ││    └──────────────────────────────┘
│  │    (Docker Container)       ││
│  │                             ││
│  │  • Processes background jobs││
│  │  • Handles async tasks      ││
│  │  • Email sending, etc.      ││
│  └─────────────────────────────┘│
│                                 │
│  ┌─────────────────────────────┐│
│  │        Redis                ││
│  │    (Docker Container)       ││
│  │                             ││
│  │  • Job queue storage        ││
│  │  • Application caching      ││
│  │  • Session storage          ││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

## 🛠️ Useful Commands

```bash
# Application Management
bin/kamal app restart          # Restart web app
bin/kamal app logs            # View app logs
bin/kamal console             # Rails console

# Job Management
bin/kamal app exec "bin/rails runner 'Sidekiq::Queue.new.clear'"  # Clear job queue
bin/kamal logs job            # View Sidekiq logs

# Redis Management
bin/kamal accessory restart redis    # Restart Redis
bin/kamal accessory logs redis      # View Redis logs

# Database Operations
bin/kamal app exec "bin/rails db:migrate"           # Run migrations
bin/kamal app exec "bin/rails db:rollback"          # Rollback migration
bin/kamal app exec "bin/rails dbconsole"            # Database console

# Deployment Management
bin/kamal deploy              # Deploy latest version
bin/kamal rollback           # Rollback to previous version
bin/kamal env push           # Update environment variables
```

## 🔒 Security Notes

- All database credentials are stored securely in `.kamal/secrets`
- SSL connection to Ubicloud PostgreSQL is recommended
- Consider setting up a firewall to restrict database access
- Your Hetzner server will have Docker security best practices applied

## 📊 Monitoring

After deployment, monitor:
- Application logs: `bin/kamal logs`
- Sidekiq job processing: Visit `/sidekiq` dashboard
- Database performance: Monitor in Ubicloud dashboard
- Server resources: Monitor in Hetzner Cloud console

## 🎉 You're Ready!

Everything is configured for a production deployment with:
- ✅ Hetzner Cloud server
- ✅ Ubicloud PostgreSQL database
- ✅ Redis + Sidekiq for jobs
- ✅ Kamal for zero-downtime deployments
- ✅ Docker for containerization

Just add your Docker Hub credentials and run `bin/kamal setup && bin/kamal deploy`!
