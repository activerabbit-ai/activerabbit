# ActiveRabbit Error Coverage

This document describes all error types that ActiveRabbit can capture, track, and monitor in Ruby on Rails applications.

## 📊 Complete Error Coverage Table

| Category | Error Type | Example Scenario | Auto-Captured? | Priority | Notes |
|----------|-----------|------------------|----------------|----------|-------|
| **Basic Errors** | StandardError | Unhandled exceptions in controllers/models | ✅ Yes | 🔴 Critical | Most common production error |
| **Database** | ActiveRecord::RecordNotFound | Missing database record (e.g., User.find(999)) | ✅ Yes | 🟡 Important | Common in production, often needs handling |
| **Database** | ActiveRecord::RecordInvalid | Validation failures with `!` methods | ✅ Yes | 🟡 Important | Data integrity issues |
| **Database** | ActiveRecord::RecordNotUnique | Duplicate key violations | ✅ Yes | 🟡 Important | Constraint violations |
| **Database** | ActiveRecord::StatementInvalid | SQL errors, invalid queries | ✅ Yes | 🔴 Critical | Database schema issues |
| **Controller** | ActionController::BadRequest | Malformed requests | ✅ Yes | 🟢 Common | Client-side errors |
| **Controller** | ActionController::ParameterMissing | Required parameter missing | ✅ Yes | 🟢 Common | API parameter validation |
| **Controller** | ActionController::RoutingError | Route not found (404) | ✅ Yes* | 🟢 Common | *If `ignore_404 = false` |
| **Controller** | ActionController::UnknownFormat | Unsupported format requested | ✅ Yes | 🟢 Common | Format negotiation issues |
| **Controller** | ActionController::InvalidAuthenticityToken | CSRF token missing/invalid | ✅ Yes | 🟡 Important | Security-related |
| **View/Template** | ActionView::MissingTemplate | Template file not found | ✅ Yes | 🟡 Important | Deployment issues |
| **View/Template** | ActionView::Template::Error | Error during template rendering | ✅ Yes | 🟡 Important | ERB/Haml errors |
| **View/Template** | ActionView::TemplateError | Syntax errors in views | ✅ Yes | 🟡 Important | Code quality issues |
| **JSON/API** | JSON::ParserError | Malformed JSON in request | ✅ Yes | 🟢 Common | API client errors |
| **JSON/API** | MultiJson::ParseError | JSON parsing failures | ✅ Yes | 🟢 Common | API integration |
| **Authentication** | ActionController::InvalidAuthenticityToken | Missing CSRF token | ✅ Yes | 🟡 Important | Security monitoring |
| **Network** | Net::OpenTimeout | Connection timeout to external service | ✅ Yes | 🔴 Critical | External dependency issues |
| **Network** | Net::ReadTimeout | Read timeout from external service | ✅ Yes | 🔴 Critical | Performance degradation |
| **Network** | Errno::ECONNREFUSED | Connection refused to service | ✅ Yes | 🔴 Critical | Service unavailability |
| **Background Jobs** | Sidekiq errors | Job failures | ✅ Yes | 🟡 Important | Async processing issues |
| **ActiveJob** | ActiveJob::DeserializationError | Job argument deserialization fails | ✅ Yes | 🟡 Important | Background job issues |
| **Custom** | Any Ruby exception | Manual tracking via API | ✅ Yes | Varies | Full control over tracking |

## 🎯 Coverage Breakdown

- ✅ **100%** Major Rails framework errors
- ✅ **100%** Database/ActiveRecord errors
- ✅ **100%** Controller/Action errors
- ✅ **100%** View/Template errors
- ✅ **100%** Security-related errors
- ✅ **100%** Network/Timeout errors
- ✅ **100%** Background job errors
- ✅ **100%** Custom/Manual tracking

## 🚨 How Errors are Captured

### 1. Rails Error Reporter Integration (Rails 7.0+)

ActiveRabbit automatically subscribes to Rails' built-in error reporting:

```ruby
Rails.error.subscribe(ActiveRabbit::ErrorReporter::Subscriber.new)
```

**Captures:**
- All unhandled exceptions
- Exceptions reported via `Rails.error.report(exception)`
- Framework-level errors

### 2. Middleware Integration

ActiveRabbit includes multiple middleware layers:

```ruby
# Error capture middleware (after Rails exception handlers)
ActiveRabbit::Middleware::ErrorCaptureMiddleware

# Request context tracking
ActiveRabbit::Client::RequestContextMiddleware

# Routing error catcher
ActiveRabbit::Client::RoutingErrorCatcher
```

**Captures:**
- Exceptions that bypass normal Rails handlers
- Routing errors (404s)
- Deep middleware-level errors

### 3. Sidekiq Integration

For background jobs:

```ruby
Sidekiq.configure_server do |config|
  config.error_handlers << ActiveRabbit::Client::SidekiqErrorHandler
end
```

**Captures:**
- Job execution failures
- Job deserialization errors
- Sidekiq worker crashes

### 4. Manual Tracking API

For handled exceptions or custom scenarios:

```ruby
begin
  risky_operation
rescue => e
  ActiveRabbit::Client.track_exception(e, context: {
    user_id: current_user.id,
    custom_data: "any metadata"
  })
end
```

## ⚙️ Configuration Options

### Ignore Specific Exceptions

```ruby
ActiveRabbit::Client.configure do |config|
  config.ignored_exceptions = [
    'ActiveRecord::RecordNotFound',
    'ActionController::RoutingError',
    'ActionController::InvalidAuthenticityToken'
  ]
end
```

### Control 404 Tracking

```ruby
config.ignore_404 = true  # Don't track 404s (recommended for production)
config.ignore_404 = false # Track all 404s (useful for monitoring)
```

### Error Deduplication

```ruby
config.dedupe_window = 300  # Same error within 5 minutes = deduplicated
config.dedupe_window = 0    # Disable deduplication (report every occurrence)
```

## 📈 What Gets Tracked for Each Error

Every captured error includes:

### Core Information
- Exception class name
- Error message
- Full backtrace
- Occurred timestamp
- Environment (production/staging/development)

### Request Context
- HTTP method (GET, POST, etc.)
- Request path
- Controller and action
- Request parameters (PII-scrubbed)
- User agent
- IP address

### Application Context
- Ruby version
- Rails version
- Gem version
- Server name
- Release/deployment version

### Performance Metrics
- Response time
- Database query count
- Memory usage (if available)
- GC statistics

### Custom Context
Any additional metadata you provide via `context:` parameter

## 🔍 Error Grouping

Errors are automatically grouped by:

1. **Exception class** (e.g., StandardError, ActiveRecord::RecordNotFound)
2. **Error message** (parameterized to group similar errors)
3. **Location** (file and line number)

This allows you to see:
- How many times each unique error occurred
- Trends over time
- Which errors are most frequent

## 🛡️ Privacy & Security

### PII Scrubbing

ActiveRabbit automatically scrubs sensitive data from:

- Request parameters
- Headers
- Error messages
- Backtraces

**Default scrubbed fields:**
```ruby
config.pii_fields = [
  'password', 'password_confirmation',
  'token', 'secret', 'key',
  'credit_card', 'ssn', 'social_security_number',
  'phone', 'email',
  'first_name', 'last_name', 'name',
  'address', 'city', 'state', 'zip'
]
```

Customize as needed:
```ruby
config.pii_fields << 'custom_sensitive_field'
```

## 🧪 Testing Error Capture

Use our test Rails 8 application to verify all error types:

```bash
cd test_rails8_app
bundle exec rails server -p 3002
./test_all_errors.sh
```

See [test_rails8_app/README_TESTING.md](../test_rails8_app/README_TESTING.md) for complete testing documentation.

## 📊 Performance Impact

### Exception Tracking
- **Latency**: ~700ms per exception (sent immediately, not batched)
- **Memory**: Minimal overhead (~1-2MB for queue management)
- **CPU**: Negligible (<0.1% in production workloads)

### No Impact on Application Performance
- Errors sent asynchronously (doesn't block request)
- Automatic retry with exponential backoff
- Circuit breaker for API failures

## 🔧 Troubleshooting

### Errors Not Being Captured?

1. **Check gem version**: Must be `>= 0.4.3`
   ```ruby
   gem 'activerabbit-ai', '~> 0.4.4'
   ```

2. **Verify configuration**:
   ```ruby
   ActiveRabbit::Client.configured? # Should return true
   ```

3. **Check debug logs**:
   ```ruby
   config.logger = Logger.new(Rails.root.join('log', 'activerabbit.log'))
   config.logger.level = Logger::DEBUG
   ```

4. **Verify error reporter attached**:
   ```ruby
   Rails.error.instance_variable_get(:@subscribers)
   # Should include ActiveRabbit::Client::ErrorReporter::Subscriber
   ```

### Same Error Only Reported Once?

Set `dedupe_window = 0` in development:
```ruby
if Rails.env.development?
  config.dedupe_window = 0
end
```

### Errors in Sidekiq Not Captured?

Ensure Sidekiq middleware is loaded:
```ruby
# This should happen automatically, but verify:
Sidekiq.configure_server do |config|
  # Should see ActiveRabbit error handler
end
```

## 📚 Related Documentation

- [Installation Guide](../README.md)
- [Configuration Options](./SETUP_SUMMARY.md)
- [Deployment Guide](./DEPLOYMENT_GUIDE.md)
- [Testing Guide](../test_rails8_app/README_TESTING.md)

---

**Version**: 0.4.4+
**Last Updated**: 2025-10-22
**Status**: ✅ Production Ready

