<p align="center">
  <img width="100%" alt="ActiveRabbit Dashboard" src="https://www.activerabbit.ai/assets/Screenshot_2025-12-19_at_15.22.57_1766186705753-C4jUqC1C.png">
</p>

<p align="center">
  <a href='https://www.activerabbit.ai'><img alt='Website' src='https://img.shields.io/badge/website-activerabbit.ai-orange?style=flat-square'/></a>
  <a href='https://rubygems.org/gems/activerabbit-ai'><img alt='Gem Version' src='https://img.shields.io/gem/v/activerabbit-ai?style=flat-square&color=red'/></a>
  <a href='https://www.npmjs.com/package/@activerabbit/nextjs'><img alt='NPM Version' src='https://img.shields.io/npm/v/@activerabbit/nextjs?style=flat-square&color=blue'/></a>
  <a href='#'><img alt='License' src='https://img.shields.io/badge/license-MIT-green?style=flat-square'/></a>
</p>

<p align="center">
  <a href="https://www.activerabbit.ai/docs">Documentation</a> •
  <a href="#features">Features</a> •
  <a href="#get-started">Get Started</a> •
  <a href="#sdks">SDKs</a> •
  <a href="#our-mission">Mission</a>
</p>

---

# [ActiveRabbit](https://www.activerabbit.ai): AI-Powered Application Monitoring for Rails & Beyond

ActiveRabbit is the **intelligent monitoring platform** built for modern Ruby on Rails developers. We combine comprehensive error tracking, performance monitoring, and **AI-powered insights** to help you ship with confidence. Stop debugging in the dark—let AI explain your errors and suggest fixes.

At a high level, ActiveRabbit provides:
- [🔴 Error Monitoring](#error-monitoring-catch-every-bug) — Automatic exception capture with AI explanations
- [⚡ Performance Monitoring](#performance-monitoring-optimize-with-confidence) — Track slow requests, N+1 queries, and bottlenecks
- [🤖 AI-Powered Insights](#ai-powered-insights-understand-errors-instantly) — Get instant explanations and fix suggestions
- [📊 Real-time Dashboard](#dashboard-see-everything-at-a-glance) — Beautiful, actionable analytics

We designed ActiveRabbit to be **dead-simple to integrate**—just a few lines of code and you're monitoring.

Read more about our [features](#features), [SDKs](#sdks), and [mission](#our-mission) below, and get started at https://www.activerabbit.ai today!

---

## Table of Contents

- [Get Started](#get-started)
- [Features](#features)
  - [Dashboard](#dashboard-see-everything-at-a-glance)
  - [Error Monitoring](#error-monitoring-catch-every-bug)
  - [Performance Monitoring](#performance-monitoring-optimize-with-confidence)
  - [AI-Powered Insights](#ai-powered-insights-understand-errors-instantly)
- [SDKs](#sdks)
- [Self-Hosted](#self-hosted)
- [Development Setup](#development-setup)
- [Our Mission](#our-mission)
- [Our Values](#our-values)
- [Contributing](#contributing)
- [License](#license)

---

## Get Started

### Cloud (Fastest Way!)

The quickest way to get started is signing up at [app.activerabbit.ai](https://app.activerabbit.ai). After creating an account, integrate with just a few lines:

#### Ruby on Rails

```ruby
# Gemfile
gem 'activerabbit-ai'
```

```ruby
# config/initializers/activerabbit.rb
ActiveRabbit::Client.configure do |config|
  config.api_key = ENV['ACTIVERABBIT_API_KEY']
  config.project_id = ENV['ACTIVERABBIT_PROJECT_ID']
  config.environment = Rails.env
end
```

That's it! 🎉 Errors, performance data, and N+1 queries are now being tracked automatically.

#### Next.js / Node.js

```bash
npm install @activerabbit/nextjs
```

```typescript
// app/layout.tsx or _app.tsx
import { ActiveRabbitProvider } from '@activerabbit/nextjs'

export default function RootLayout({ children }) {
  return (
    <ActiveRabbitProvider
      projectId={process.env.NEXT_PUBLIC_ACTIVERABBIT_PROJECT_ID}
      apiKey={process.env.ACTIVERABBIT_API_KEY}
    >
      {children}
    </ActiveRabbitProvider>
  )
}
```

---

## Features

### Dashboard: See Everything at a Glance

Get a bird's-eye view of your application's health with our real-time dashboard. Track error rates, performance metrics, and trends—all in one beautiful interface.

- **Real-time Error Counts**: See errors as they happen
- **Performance Overview**: P50, P95, P99 response times at a glance
- **Trend Analysis**: Spot regressions before they become incidents
- **Multi-Project Support**: Monitor all your apps from one place

<p align="center">
  <img width="800" alt="ActiveRabbit Dashboard" src="https://www.activerabbit.ai/assets/Screenshot_2025-12-19_at_15.22.57_1766186705753-C4jUqC1C.png">
</p>

---

### Error Monitoring: Catch Every Bug

Comprehensive error tracking with detailed context, stack traces, and automatic grouping. Never miss a bug again.

- **Automatic Exception Capture**: Rails, Sidekiq, and custom errors
- **Smart Error Grouping**: Reduce noise by grouping similar errors
- **Rich Context**: Request data, user info, environment details
- **Stack Trace Navigation**: Jump directly to the problematic code
- **Customizable Alerts**: Slack, email, webhooks—get notified your way

<p align="center">
  <img width="800" alt="Error Monitoring" src="https://www.activerabbit.ai/assets/Screenshot_2025-12-19_at_15.22.54_1766186693045-Dic7bIVJ.png">
</p>

---

### Performance Monitoring: Optimize with Confidence

Track application performance across your entire stack. Identify slow endpoints, database bottlenecks, and N+1 queries automatically.

- **Request Tracing**: See exactly where time is spent
- **N+1 Query Detection**: Automatically catch database anti-patterns
- **Slow Query Alerts**: Get notified when queries exceed thresholds
- **Percentile Metrics**: P50, P95, P99 tracking for accurate insights
- **Trend Analysis**: Compare performance across deploys

<p align="center">
  <img width="800" alt="Performance Monitoring" src="https://www.activerabbit.ai/assets/Screenshot_2025-12-19_at_15.22.52_1766186695512-C0l8UIYw.png">
</p>

---

### AI-Powered Insights: Understand Errors Instantly

**This is what sets ActiveRabbit apart.** Our AI analyzes every error and provides:

- **Plain-English Explanations**: Understand what went wrong without diving deep into code
- **Root Cause Analysis**: AI identifies the likely cause of the error
- **Fix Suggestions**: Get actionable recommendations to resolve issues
- **Pattern Recognition**: AI spots recurring issues and anti-patterns
- **Context-Aware**: AI considers your stack trace, request data, and environment

<p align="center">
  <img width="800" alt="AI-Powered Error Explanation" src="https://www.activerabbit.ai/assets/Screenshot_2025-12-19_at_15.23.47_1766186702234-LtM7FfRF.png">
</p>

> 💡 **Example**: Instead of just seeing `NoMethodError: undefined method 'name' for nil:NilClass`, ActiveRabbit AI tells you: *"This error occurs because `user` is nil when trying to access `name`. This typically happens when a database query returns no results. Consider adding a nil check or using `&.name` (safe navigation operator)."*

---

## SDKs

| Platform | Package | Status |
|----------|---------|--------|
| **Ruby on Rails** | [`activerabbit-ai`](https://rubygems.org/gems/activerabbit-ai) | ✅ Stable |
| **Next.js** | [`@activerabbit/nextjs`](https://www.npmjs.com/package/@activerabbit/nextjs) | ✅ Stable |
| **Node.js** | `@activerabbit/node` | 🚧 Coming Soon |
| **Python/Django** | `activerabbit-python` | 🚧 Coming Soon |

### Ruby SDK Features

```ruby
# Automatic error tracking - just works!
# Manual tracking when needed:
begin
  risky_operation
rescue => e
  ActiveRabbit::Client.track_exception(e, context: { user_id: user.id })
  raise
end

# Performance monitoring
ActiveRabbit::Client.performance_monitor.measure('heavy_operation') do
  perform_heavy_calculation
end

# Custom events
ActiveRabbit::Client.track_event('user_signup', { plan: 'premium' })
```

### What Gets Tracked Automatically

| Category | What's Tracked |
|----------|----------------|
| **Errors** | `StandardError`, `NoMethodError`, `ActiveRecord::*`, `ActionController::*`, and 20+ more |
| **Performance** | Controller actions, database queries, view renders, background jobs |
| **Database** | N+1 queries, slow queries, connection issues |
| **Background Jobs** | Sidekiq jobs, ActiveJob, failures and retries |

---

## Self-Hosted

Deploy ActiveRabbit on your own infrastructure with Docker:

```bash
git clone https://github.com/activerabbit/activerabbit
cd activerabbit
docker-compose up -d
```

After setup, access the dashboard at `http://localhost:3000`.

**Requirements:**
- Docker & Docker Compose
- PostgreSQL
- Redis
- 4GB+ RAM recommended

See our [Self-Hosted Guide](./DOCKER_SETUP.md) for detailed instructions.

---

## Development Setup

### Prerequisites

- Ruby 3.2.3+
- PostgreSQL
- Redis
- Node.js (for asset compilation)

### Quick Start

```bash
# Clone and install
git clone https://github.com/activerabbit/activerabbit
cd activerabbit
bundle install

# Setup environment
cp .env.example .env
# Edit .env with your settings

# Setup database
rails db:create db:migrate

# Start all services
bin/dev
```

### Docker Development

```bash
# First-time setup
./bin/docker-setup

# Start all services
docker-compose up

# Or run in background
docker-compose up -d
```

### Helper Scripts

| Script | Description |
|--------|-------------|
| `bin/dev` | Start development server with all services |
| `bin/docker-setup` | First-time Docker setup |
| `bin/docker-dev` | Start Docker development environment |
| `bin/docker-console` | Open Rails console in Docker |
| `bin/docker-reset` | Reset entire Docker environment |

### Ports

| Service | Port |
|---------|------|
| Web Application | http://localhost:3000 |
| Sidekiq Dashboard | http://localhost:3000/sidekiq |
| PostgreSQL | localhost:5432 |
| Redis | localhost:6380 |

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| **Framework** | Ruby on Rails 8.2 |
| **Database** | PostgreSQL |
| **Cache/Jobs** | Redis, Sidekiq |
| **Authentication** | Devise |
| **Payments** | Stripe (Pay gem) |
| **UI** | Tailwind CSS |
| **Security** | Rack::Attack |
| **HTTP Client** | Faraday |
| **Metrics** | HDRHistogram |

---

## Our Mission

Our mission is to help Ruby developers **ship faster and debug less**. We believe:

1. **Monitoring should be effortless** — Integration should take minutes, not days
2. **Errors should be understandable** — AI can bridge the gap between stack traces and solutions
3. **Performance matters** — Slow apps lose users; we help you stay fast
4. **Rails deserves great tooling** — The Ruby ecosystem deserves modern monitoring

---

## Our Values

### 🔓 We build in the open

ActiveRabbit is designed with transparency in mind. Our roadmap, decisions, and codebase reflect our commitment to the community.

### 🎯 We build a cohesive product

Error tracking, performance monitoring, and AI insights aren't separate products—they're one unified experience. Every feature is designed to work seamlessly together.

### 💎 We build for Rails developers

We're Rails developers ourselves. We understand the ecosystem, the patterns, and the pain points. ActiveRabbit is built by Rails devs, for Rails devs.

### 🤖 We embrace AI thoughtfully

AI isn't a gimmick—it's a tool that genuinely helps you debug faster. Our AI features are practical, accurate, and designed to save you time.

---

## Documentation

- **[Error Coverage Guide](docs/ERROR_COVERAGE.md)** - Complete list of 20+ error types ActiveRabbit can track
- [Deployment Guide](docs/DEPLOYMENT_GUIDE.md)
- [Setup Summary](docs/SETUP_SUMMARY.md)
- [How to Error Tracking](docs/HOW_TO_ERROR_TRACKING.md)
- [Slack Integration](docs/SLACK_INTEGRATION.md)
- [Account Slack Notifications](docs/ACCOUNT_SLACK_NOTIFICATIONS.md)
- [Fizzy Integration](docs/FIZZY_INTEGRATION.md) - Sync errors to Fizzy boards

---

## Contributing

We welcome contributions! Here's how to get started:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test
bundle exec rspec spec/models/user_spec.rb

# Run with coverage
COVERAGE=true bundle exec rspec
```

---

## License

This project is licensed under the MIT License - see the [LICENCE](./LICENCE) file for details.

---

<p align="center">
  <strong>Built with ❤️ for the Ruby community</strong>
</p>

<p align="center">
  <a href="https://www.activerabbit.ai">Website</a> •
  <a href="https://www.activerabbit.ai/docs">Docs</a> •
  <a href="https://twitter.com/activerabbit">Twitter</a>
</p>
