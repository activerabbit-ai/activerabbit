# Fix for ActiveRecord::RecordNotFound

**Issue ID:** 764
**Generated:** 2026-01-22 19:41 UTC
**Status:** 📋 Suggestion only (manual review required)

## Suggested Code Fix

```ruby
@scraper_job = ScraperJob.find_by(slug: params[:id])

raise ActiveRecord::RecordNotFound unless @scraper_job
```

## Full Analysis

## 🐛 Bug Fix: ActiveRecord::RecordNotFound

**Issue ID:** #764
**Controller:** `ScraperJobsController#show`
**Occurrences:** 58 times
**First seen:** 2026-01-18 08:34
**Last seen:** 2026-01-22 16:40

## 🔍 Root Cause Analysis

The error `ActiveRecord::RecordNotFound` is raised because the `@scraper_job` variable is `nil`. This occurs when no record matches the `slug` value provided in the `params[:id]`. The `find_by` method is used to retrieve the record, but it returns `nil` if no matching record is found, leading to the exception being raised.

## 🔧 Suggested Fix

To fix this issue, ensure that the `@scraper_job` is properly assigned by using the `find_by` method and handling the case where no record is found. Here's how you can modify the code:

**Before:**
```ruby
@scraper_job = ScraperJob.find_by(
  where: {slug: params[:id]},
  load: false,
  limit: 1,
).first

raise ActiveRecord::RecordNotFound unless @scraper_job
```

**After:**
```ruby
@scraper_job = ScraperJob.find_by(slug: params[:id])

raise ActiveRecord::RecordNotFound unless @scraper_job
```

## 📋 Error Details

**Error Message:**
```
ActiveRecord::RecordNotFound
```

**Stack Trace (top frames):**
```
["/rails/app/controllers/scraper_jobs_controller.rb:13:in `show'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_controller/metal/basic_implicit_render.rb:8:in `send_action'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/abstract_controller/base.rb:226:in `process_action'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_controller/metal/rendering.rb:193:in `process_action'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/abstract_controller/callbacks.rb:261:in `block in process_action'", "/usr/local/bundle/ruby/3.3.0/gems/activesupport-8.0.0.rc2/lib/active_support/callbacks.rb:120:in `block in run_callbacks'", "/usr/local/bundle/ruby/3.3.0/gems/i18n-1.14.6/lib/i18n.rb:353:in `with_locale'", "/rails/app/controllers/concerns/set_locale.rb:13:in `set_locale'", "/usr/local/bundle/ruby/3.3.0/gems/activesupport-8.0.0.rc2/lib/active_support/callbacks.rb:129:in `block in run_callbacks'", "/usr/local/bundle/ruby/3.3.0/gems/turbo-rails-2.0.11/lib/turbo-rails.rb:24:in `with_request_id'", "/usr/local/bundle/ruby/3.3.0/gems/turbo-rails-2.0.11/app/controllers/concerns/turbo/request_id_tracking.rb:10:in `turbo_tracking_request_id'", "/usr/local/bundle/ruby/3.3.0/gems/activesupport-8.0.0.rc2/lib/active_support/callbacks.rb:129:in `block in run_callbacks'", "/usr/local/bundle/ruby/3.3.0/gems/actiontext-8.0.0.rc2/lib/action_text/rendering.rb:25:in `with_renderer'", "/usr/local/bundle/ruby/3.3.0/gems/actiontext-8.0.0.rc2/lib/action_text/engine.rb:71:in `block (4 levels) in <class:Engine>'", "/usr/local/bundle/ruby/3.3.0/gems/activesupport-8.0.0.rc2/lib/active_support/callbacks.rb:129:in `instance_exec'", "/usr/local/bundle/ruby/3.3.0/gems/activesupport-8.0.0.rc2/lib/active_support/callbacks.rb:129:in `block in run_callbacks'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-rails-6.2.0/lib/sentry/rails/controller_transaction.rb:21:in `block in sentry_around_action'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-ruby-6.2.0/lib/sentry/hub.rb:146:in `block in with_child_span'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-ruby-6.2.0/lib/sentry/span.rb:232:in `with_child_span'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-ruby-6.2.0/lib/sentry/hub.rb:144:in `with_child_span'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-ruby-6.2.0/lib/sentry-ruby.rb:525:in `with_child_span'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-rails-6.2.0/lib/sentry/rails/controller_transaction.rb:18:in `sentry_around_action'", "/usr/local/bundle/ruby/3.3.0/gems/activesupport-8.0.0.rc2/lib/active_support/callbacks.rb:129:in `block in run_callbacks'", "/usr/local/bundle/ruby/3.3.0/gems/activesupport-8.0.0.rc2/lib/active_support/callbacks.rb:140:in `run_callbacks'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/abstract_controller/callbacks.rb:260:in `process_action'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_controller/metal/rescue.rb:27:in `process_action'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_controller/metal/instrumentation.rb:76:in `block in process_action'", "/usr/local/bundle/ruby/3.3.0/gems/activesupport-8.0.0.rc2/lib/active_support/notifications.rb:210:in `block in instrument'", "/usr/local/bundle/ruby/3.3.0/gems/activesupport-8.0.0.rc2/lib/active_support/notifications/instrumenter.rb:58:in `instrument'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-rails-6.2.0/lib/sentry/rails/tracing.rb:56:in `instrument'", "/usr/local/bundle/ruby/3.3.0/gems/activesupport-8.0.0.rc2/lib/active_support/notifications.rb:210:in `instrument'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_controller/metal/instrumentation.rb:75:in `process_action'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_controller/metal/params_wrapper.rb:259:in `process_action'", "/usr/local/bundle/ruby/3.3.0/gems/searchkick-5.4.0/lib/searchkick/controller_runtime.rb:15:in `process_action'", "/usr/local/bundle/ruby/3.3.0/gems/activerecord-8.0.0.rc2/lib/active_record/railties/controller_runtime.rb:39:in `process_action'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/abstract_controller/base.rb:163:in `process'", "/usr/local/bundle/ruby/3.3.0/gems/actionview-8.0.0.rc2/lib/action_view/rendering.rb:40:in `process'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_controller/metal.rb:252:in `dispatch'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_controller/metal.rb:335:in `dispatch'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/routing/route_set.rb:67:in `dispatch'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/routing/route_set.rb:50:in `serve'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/journey/router.rb:53:in `block in serve'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/journey/router.rb:133:in `block in find_routes'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/journey/router.rb:126:in `each'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/journey/router.rb:126:in `find_routes'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/journey/router.rb:34:in `serve'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/routing/route_set.rb:908:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/omniauth-2.1.2/lib/omniauth/strategy.rb:202:in `call!'", "/usr/local/bundle/ruby/3.3.0/gems/omniauth-2.1.2/lib/omniauth/strategy.rb:169:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/warden-1.2.9/lib/warden/manager.rb:36:in `block in call'", "/usr/local/bundle/ruby/3.3.0/gems/warden-1.2.9/lib/warden/manager.rb:34:in `catch'", "/usr/local/bundle/ruby/3.3.0/gems/warden-1.2.9/lib/warden/manager.rb:34:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/rack-3.1.8/lib/rack/tempfile_reaper.rb:20:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/rack-3.1.8/lib/rack/etag.rb:29:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/rack-3.1.8/lib/rack/conditional_get.rb:31:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/rack-3.1.8/lib/rack/head.rb:15:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/http/permissions_policy.rb:38:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/http/content_security_policy.rb:35:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/rack-session-2.0.0/lib/rack/session/abstract/id.rb:272:in `context'", "/usr/local/bundle/ruby/3.3.0/gems/rack-session-2.0.0/lib/rack/session/abstract/id.rb:266:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/middleware/cookies.rb:706:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/middleware/callbacks.rb:31:in `block in call'", "/usr/local/bundle/ruby/3.3.0/gems/activesupport-8.0.0.rc2/lib/active_support/callbacks.rb:100:in `run_callbacks'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/middleware/callbacks.rb:30:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-rails-6.2.0/lib/sentry/rails/rescued_exception_interceptor.rb:14:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/activerabbit-ai-0.6.1/lib/active_rabbit/middleware/error_capture_middleware.rb:11:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/middleware/debug_exceptions.rb:31:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-ruby-6.2.0/lib/sentry/rack/capture_exceptions.rb:30:in `block (2 levels) in call'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-ruby-6.2.0/lib/sentry/hub.rb:310:in `with_session_tracking'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-ruby-6.2.0/lib/sentry-ruby.rb:418:in `with_session_tracking'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-ruby-6.2.0/lib/sentry/rack/capture_exceptions.rb:21:in `block in call'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-ruby-6.2.0/lib/sentry/hub.rb:89:in `with_scope'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-ruby-6.2.0/lib/sentry-ruby.rb:398:in `with_scope'", "/usr/local/bundle/ruby/3.3.0/gems/sentry-ruby-6.2.0/lib/sentry/rack/capture_exceptions.rb:20:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/middleware/show_exceptions.rb:32:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/railties-8.0.0.rc2/lib/rails/rack/logger.rb:41:in `call_app'", "/usr/local/bundle/ruby/3.3.0/gems/railties-8.0.0.rc2/lib/rails/rack/logger.rb:29:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/railties-8.0.0.rc2/lib/rails/rack/silence_request.rb:28:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/middleware/remote_ip.rb:96:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/middleware/request_id.rb:34:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/rack-3.1.8/lib/rack/method_override.rb:28:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/rack-3.1.8/lib/rack/runtime.rb:24:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/middleware/executor.rb:16:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/middleware/static.rb:27:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/rack-3.1.8/lib/rack/sendfile.rb:114:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/middleware/ssl.rb:92:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/actionpack-8.0.0.rc2/lib/action_dispatch/middleware/assume_ssl.rb:24:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/railties-8.0.0.rc2/lib/rails/engine.rb:535:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/puma-6.5.0/lib/puma/configuration.rb:279:in `call'", "/usr/local/bundle/ruby/3.3.0/gems/puma-6.5.0/lib/puma/request.rb:99:in `block in handle_request'", "/usr/local/bundle/ruby/3.3.0/gems/puma-6.5.0/lib/puma/thread_pool.rb:389:in `with_force_shutdown'", "/usr/local/bundle/ruby/3.3.0/gems/puma-6.5.0/lib/puma/request.rb:98:in `handle_request'", "/usr/local/bundle/ruby/3.3.0/gems/puma-6.5.0/lib/puma/server.rb:468:in `process_client'", "/usr/local/bundle/ruby/3.3.0/gems/puma-6.5.0/lib/puma/server.rb:249:in `block in run'", "/usr/local/bundle/ruby/3.3.0/gems/puma-6.5.0/lib/puma/thread_pool.rb:166:in `block in spawn_thread'"]
```

**Request Context:**
- Method: `GET`
- Path: `/show/4b6efc037b85b1da0aa697bdc26d7955a48bcea43680f68625cc284bf95fc122`

## 🛡️ Prevention

1. **Use `find_by` for Optional Records:** Use `find_by` instead of `where(...).first` to directly handle cases where a record might not be found.
2. **Graceful Error Handling:** Consider using a `rescue_from` block in the controller to handle `ActiveRecord::RecordNotFound` exceptions gracefully, perhaps by redirecting to a 404 page.
3. **Parameter Validation:** Validate and sanitize input parameters to ensure they are in the expected format before querying the database.

## ✅ Checklist

- [ ] Code fix implemented
- [ ] Tests added/updated
- [ ] Error scenario manually verified
- [ ] No regressions introduced

---
_Generated by [ActiveRabbit](https://activerabbit.ai) AI_

---
_Generated by [ActiveRabbit](https://activerabbit.ai) AI_