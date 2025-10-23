# ActiveRabbit

A comprehensive application monitoring and error tracking platform built with Rails 8.2, featuring real-time monitoring, performance analytics, and intelligent alerting.

## 🚀 Stack

- **Framework**: Ruby on Rails 8.2
- **Database**: PostgreSQL
- **Background Jobs**: Sidekiq + Redis
- **Authentication**: Devise
- **Billing**: Pay (Stripe integration)
- **UI**: Tailwind CSS
- **Security**: Rack::Attack
- **HTTP Client**: Faraday
- **Metrics**: HDRHistogram
- **Environment**: dotenv-rails

## 📋 Prerequisites

- Ruby 3.2.3+
- PostgreSQL
- Redis
- Node.js (for asset compilation)
- Stripe account (for payments)

## 🛠 Quick Setup

### 1. Clone and Install

```bash
git clone <repository-url>
cd activerabbit
bundle install
```

### 2. Environment Configuration

Copy the example environment file and configure your settings:

```bash
cp .env.example .env
```

Edit `.env` with your actual values:

```env
# Database
DATABASE_URL=postgresql://username:password@localhost:5432/activerabbit_development

# Redis
REDIS_URL=redis://localhost:6379/0

# Stripe (get from https://dashboard.stripe.com/test/apikeys)
STRIPE_PUBLIC_KEY=pk_test_your_stripe_public_key_here
STRIPE_SECRET_KEY=sk_test_your_stripe_secret_key_here
STRIPE_SIGNING_SECRET=whsec_your_stripe_webhook_secret_here
```

### 3. Database Setup

```bash
rails db:create
rails db:migrate
```

### 4. Start Services

#### Option A: Full Docker Setup (Recommended)

```bash
# Setup everything in Docker (first time only)
./bin/docker-setup

# Start all services
docker-compose up

# Or start in background
docker-compose up -d
```

#### Option B: Docker + Local Rails

```bash
docker-compose up -d db redis
rails server
```

#### Option C: Local Services

Start PostgreSQL and Redis locally, then:

```bash
bin/dev
```

This starts:
- Rails server (port 3000)
- Sidekiq worker
- CSS/JS build watchers

## 🔧 Configuration Details

### Devise Authentication

The application comes with Devise pre-configured with:
- User registration/login
- Password reset
- Email confirmation (optional)
- Trackable (sign-in tracking)

**Default routes:**
- `/users/sign_up` - Registration
- `/users/sign_in` - Login
- `/users/sign_out` - Logout

### Stripe Payments (Pay Gem)

The Pay gem is configured for Stripe integration:

1. **Setup Stripe webhooks** in your Stripe dashboard:
   - Endpoint URL: `https://your-domain.com/payments/webhooks/stripe`
   - Events: `invoice.payment_succeeded`, `customer.subscription.deleted`, etc.

2. **Create products** in Stripe dashboard and update the price IDs in:
   - `app/controllers/subscriptions_controller.rb`

3. **Test payments** using Stripe test cards:
   - Success: `4242 4242 4242 4242`
   - Decline: `4000 0000 0000 0002`

### Sidekiq Background Jobs

- **Web UI**: Visit `/sidekiq` (protect in production)
- **Redis connection**: Configured in `config/initializers/sidekiq.rb`
- **Job queues**: Default queue configuration

### Rack::Attack Security

Pre-configured rate limiting:
- 300 requests per 5 minutes per IP
- 5 login attempts per 20 seconds
- Protection against common attacks

### Tailwind CSS

- **Build command**: `rails tailwindcss:build`
- **Watch mode**: `rails tailwindcss:watch`
- **Custom styles**: `app/assets/tailwind/application.css`

## 🚀 Development Commands

### Terminal Commands Used to Create This App

```bash
# 1. Create Rails app
rails new activerabbit --database=postgresql --skip-test --skip-system-test --skip-jbuilder

# 2. Add gems to Gemfile
bundle add devise sidekiq pay tailwindcss-rails rack-attack faraday HDRHistogram dotenv-rails

# 3. Install and configure
rails generate devise:install
rails generate devise User
rails generate devise:views
rails tailwindcss:install

# 4. Create controllers and views
rails generate controller Home index
rails generate controller Subscriptions

# 5. Database setup
rails db:create db:migrate
```

### Useful Development Commands

```bash
# Start development server with all services
bin/dev

# Run migrations
rails db:migrate

# Generate Devise views for customization
rails generate devise:views

# Access Rails console
rails console

# View background jobs
open http://localhost:3000/sidekiq

# Build CSS
rails tailwindcss:build

# Run Sidekiq worker
bundle exec sidekiq

# Reset database
rails db:drop db:create db:migrate
```

## 🐳 Docker Development

### Quick Start with Docker

```bash
# First-time setup
./bin/docker-setup

# Start all services (web, sidekiq, db, redis)
docker-compose up

# Start in background
docker-compose up -d

# View logs
docker-compose logs -f web
docker-compose logs -f sidekiq

# Stop all services
docker-compose down
```

### Docker Helper Scripts

```bash
# Setup everything (first time)
./bin/docker-setup

# Start development environment
./bin/docker-dev

# Open Rails console in Docker
./bin/docker-console

# Reset entire environment (deletes data!)
./bin/docker-reset
```

### Individual Service Management

```bash
# Start specific services
docker-compose up -d db redis
docker-compose up web sidekiq

# Rebuild containers
docker-compose build
docker-compose up --build

# Run one-off commands
docker-compose run --rm web bundle exec rails console
docker-compose run --rm web bundle exec rails db:migrate
```

### Database in Docker

```bash
# Connect to PostgreSQL in Docker
docker-compose exec db psql -U postgres -d activerabbit_development

# Run migrations
docker-compose exec web bundle exec rails db:migrate

# Reset database
docker-compose exec web bundle exec rails db:drop db:create db:migrate
```

### Docker Ports

- **Web Application**: http://localhost:3000
- **Sidekiq Dashboard**: http://localhost:3000/sidekiq
- **PostgreSQL**: localhost:5432
- **Redis**: localhost:6380 (mapped from 6379 to avoid conflicts)

## 🔒 Security Features

### Rack::Attack Configuration

- **Rate limiting**: Prevents abuse
- **IP blocking**: Blocks malicious IPs
- **Login throttling**: Prevents brute force attacks
- **Fail2ban**: Automatic IP banning for suspicious activity

### Devise Security

- **Password complexity**: Enforced by Devise
- **Session management**: Secure session handling
- **CSRF protection**: Built-in Rails protection

## 💳 Payment Integration Examples

### Create a Subscription

```ruby
# In your controller
def create_subscription
  current_user.payment_processor.subscribe(
    name: "Basic Plan",
    plan: "price_1234567890" # Your Stripe price ID
  )
end
```

### Check Subscription Status

```ruby
# In your views or controllers
if current_user.subscribed?
  # User has active subscription
else
  # User needs to subscribe
end
```

### Handle Webhooks

Pay gem automatically handles Stripe webhooks for:
- Successful payments
- Failed payments
- Subscription updates
- Customer updates

## 🚀 Deployment

### Environment Variables for Production

```env
# Required for production
SECRET_KEY_BASE=your_secret_key_base
RAILS_MASTER_KEY=your_rails_master_key
DATABASE_URL=postgresql://user:pass@host:5432/dbname
REDIS_URL=redis://host:6379/0

# Stripe live keys
STRIPE_PUBLIC_KEY=pk_live_...
STRIPE_SECRET_KEY=sk_live_...
STRIPE_SIGNING_SECRET=whsec_...

# Email configuration
SMTP_ADDRESS=smtp.sendgrid.net
SMTP_USERNAME=apikey
SMTP_PASSWORD=your_sendgrid_api_key
```

### Heroku Deployment

```bash
# Create Heroku app
heroku create your-app-name

# Add addons
heroku addons:create heroku-postgresql:hobby-dev
heroku addons:create heroku-redis:hobby-dev

# Set environment variables
heroku config:set STRIPE_PUBLIC_KEY=pk_live_...
heroku config:set STRIPE_SECRET_KEY=sk_live_...

# Deploy
git push heroku main
heroku run rails db:migrate
```

## 🧪 Testing

### Test Suite Setup

```bash
# Add to Gemfile (test group)
gem 'rspec-rails'
gem 'factory_bot_rails'
gem 'capybara'

# Install
bundle install
rails generate rspec:install
```

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test
bundle exec rspec spec/models/user_spec.rb

# Run with coverage
COVERAGE=true bundle exec rspec
```

## 📚 Documentation

### Platform Documentation
- **[Error Coverage Guide](docs/ERROR_COVERAGE.md)** - Complete list of 20+ error types ActiveRabbit can track
- [Deployment Guide](docs/DEPLOYMENT_GUIDE.md)
- [Setup Summary](docs/SETUP_SUMMARY.md)
- [How to Error Tracking](docs/HOW_TO_ERROR_TRACKING.md)
- [Slack Integration](docs/SLACK_INTEGRATION.md)
- [Account Slack Notifications](docs/ACCOUNT_SLACK_NOTIFICATIONS.md)

### Test Application
- [Test Rails 8 App](../test_rails8_app/README_TESTING.md) - Verify all error types are captured

### External Resources
- [Rails Guides](https://guides.rubyonrails.org/)
- [Devise Documentation](https://github.com/heartcombo/devise)
- [Pay Gem Documentation](https://github.com/pay-rails/pay)
- [Stripe API Documentation](https://stripe.com/docs/api)
- [Sidekiq Documentation](https://github.com/mperham/sidekiq)
- [Tailwind CSS Documentation](https://tailwindcss.com/docs)

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

echo ""
echo "3. NoMethodError:"
echo 'curl -X POST http://localhost:3000/api/v1/events/errors \
  -H "Content-Type: application/json" \
  -H "X-Project-Token: 3d241ebb28fb9dc2e4f9c7cb6a644c4c4102368d9d14a5ad4ff9c9cd6f1e6dce" \
  -d "{
    \"exception_class\": \"NoMethodError\",
    \"message\": \"undefined method `invalid_method` for nil:NilClass\",
    \"backtrace\": [\"app/controllers/test_controller.rb:25:in database_test\", \"app/models/user.rb:45:in find_by_email\"],
    \"controller_action\": \"TestController#database_test\",
    \"request_path\": \"/test/database\",
    \"request_method\": \"POST\",
    \"occurred_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
  }"'


curl -X POST http://localhost:3000/api/v1/events/errors \
  -H "Content-Type: application/json" \
  -H "X-Project-Token: f6ce4c38001115e8aa7d43db3791086d191ade9c6abeec874bfc18be5fff78a2" \
  -d '{
    "exception_class": "NewMethodError",
    "message": "undefined method `invalid_method` for nil:NilClass",
    "backtrace": ["app/controllers/new_controller.rb:25:in database_test", "app/models/user.rb:45:in find_by_email"],
    "controller_action": "NewController#database_test",
    "request_path": "/test/database",
    "request_method": "POST",
    "occurred_at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  }'

{"status":"created","message":"Error event queued for processing","data":{"project_id":1,"exception_class":"NewMethodError"}}%

