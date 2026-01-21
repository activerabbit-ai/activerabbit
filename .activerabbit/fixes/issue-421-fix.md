# Fix for AbstractController::ActionNotFound

**Issue ID:** 421
**Generated:** 2026-01-21 23:53 UTC
**Status:** 📋 Suggestion only (manual review required)

## Full Analysis

## 🐛 Bug Fix: AbstractController::ActionNotFound

**Issue ID:** #421
**Controller:** `UsersController#show`
**Occurrences:** 55 times
**First seen:** 2025-12-31 00:26
**Last seen:** 2026-01-15 06:38

## 🔍 Root Cause Analysis

Analysis pending. Please review the stack trace below.

## 🔧 Suggested Fix

Manual review required. See error context below.

## 📋 Error Details

**Error Message:**
```
The action 'show' could not be found for UsersController
```

**Stack Trace (top frames):**
```
["/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/abstract_controller/base.rb:158:in `process'", "/usr/local/bundle/ruby/3.2.0/gems/actionview-8.0.2.1/lib/action_view/rendering.rb:40:in `process'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_controller/metal.rb:252:in `dispatch'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_controller/metal.rb:335:in `dispatch'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/routing/route_set.rb:67:in `dispatch'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/routing/route_set.rb:50:in `serve'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/journey/router.rb:53:in `block in serve'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/journey/router.rb:133:in `block in find_routes'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/journey/router.rb:126:in `each'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/journey/router.rb:126:in `find_routes'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/journey/router.rb:34:in `serve'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/routing/route_set.rb:908:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/omniauth-2.1.4/lib/omniauth/strategy.rb:202:in `call!'", "/usr/local/bundle/ruby/3.2.0/gems/omniauth-2.1.4/lib/omniauth/strategy.rb:169:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/omniauth-2.1.4/lib/omniauth/strategy.rb:202:in `call!'", "/usr/local/bundle/ruby/3.2.0/gems/omniauth-2.1.4/lib/omniauth/strategy.rb:169:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-attack-6.7.0/lib/rack/attack.rb:103:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-attack-6.7.0/lib/rack/attack.rb:127:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/warden-1.2.9/lib/warden/manager.rb:36:in `block in call'", "/usr/local/bundle/ruby/3.2.0/gems/warden-1.2.9/lib/warden/manager.rb:34:in `catch'", "/usr/local/bundle/ruby/3.2.0/gems/warden-1.2.9/lib/warden/manager.rb:34:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/tempfile_reaper.rb:20:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/etag.rb:29:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/conditional_get.rb:31:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/head.rb:15:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/http/permissions_policy.rb:38:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/http/content_security_policy.rb:38:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-session-2.1.1/lib/rack/session/abstract/id.rb:274:in `context'", "/usr/local/bundle/ruby/3.2.0/gems/rack-session-2.1.1/lib/rack/session/abstract/id.rb:268:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/cookies.rb:706:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/callbacks.rb:31:in `block in call'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:100:in `run_callbacks'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/callbacks.rb:30:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/activerabbit-ai-0.6.1/lib/active_rabbit/middleware/error_capture_middleware.rb:11:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/debug_exceptions.rb:31:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/show_exceptions.rb:32:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/railties-8.0.2.1/lib/rails/rack/logger.rb:41:in `call_app'", "/usr/local/bundle/ruby/3.2.0/gems/railties-8.0.2.1/lib/rails/rack/logger.rb:29:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/railties-8.0.2.1/lib/rails/rack/silence_request.rb:28:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/remote_ip.rb:96:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/request_id.rb:34:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/method_override.rb:28:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/runtime.rb:24:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/cache/strategy/local_cache_middleware.rb:29:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/executor.rb:16:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/static.rb:27:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/sendfile.rb:114:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/assume_ssl.rb:24:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/railties-8.0.2.1/lib/rails/engine.rb:535:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/configuration.rb:279:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/request.rb:99:in `block in handle_request'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/thread_pool.rb:390:in `with_force_shutdown'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/request.rb:98:in `handle_request'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/server.rb:472:in `process_client'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/server.rb:254:in `block in run'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/thread_pool.rb:167:in `block in spawn_thread'"]
```

**Request Context:**
- Method: `GET`
- Path: `/users/sign_up`

## ✅ Checklist

- [ ] Code fix implemented
- [ ] Tests added/updated
- [ ] Error scenario manually verified
- [ ] No regressions introduced

---
_Generated by [ActiveRabbit](https://activerabbit.ai) AI_

---
_Generated by [ActiveRabbit](https://activerabbit.ai) AI_