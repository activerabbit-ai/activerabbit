# Fix for ActiveRecord::RecordNotFound

**Issue ID:** 757
**Generated:** 2026-01-21 01:02 UTC
**Status:** ✅ Code fix automatically applied

> **Note:** An actual code fix has been applied to the source file in this PR.
> Please review the changes carefully before merging.

## Full Analysis

## 🐛 Bug Fix: ActiveRecord::RecordNotFound

**Issue ID:** #757
**Controller:** `ProjectSettingsController#show`
**Occurrences:** 1 times
**First seen:** 2026-01-18 06:24
**Last seen:** 2026-01-18 06:24

## 🔍 Root Cause Analysis

The error occurs because the `set_project` method is attempting to find a `Project` with `id` "1" associated with the current account, but no such project exists in the database. This results in an `ActiveRecord::RecordNotFound` exception.

## 🔧 Suggested Fix

Modify the `set_project` method to handle the case where the project is not found by using `find_by` instead of `find`, which returns `nil` instead of raising an exception. Then, handle the `nil` case appropriately.

### Before
```ruby
@project = current_account.projects.find(params[:project_id])  # <-- ERROR HERE
```

### After
```ruby
@project = current_account.projects.find_by(id: params[:project_id])
unless @project
  redirect_to dashboard_path, alert: "Project not found."
end
```

## 📋 Error Details

**Error Message:**
```
Couldn't find Project with 'id'="1" [WHERE "projects"."account_id" = $1]
```

**Stack Trace (top frames):**
```
["/usr/local/bundle/ruby/3.2.0/gems/activerecord-8.0.2.1/lib/active_record/relation/finder_methods.rb:429:in `raise_record_not_found_exception!'", "/usr/local/bundle/ruby/3.2.0/gems/activerecord-8.0.2.1/lib/active_record/relation/finder_methods.rb:537:in `find_one'", "/usr/local/bundle/ruby/3.2.0/gems/activerecord-8.0.2.1/lib/active_record/relation/finder_methods.rb:514:in `find_with_ids'", "/usr/local/bundle/ruby/3.2.0/gems/activerecord-8.0.2.1/lib/active_record/relation/finder_methods.rb:100:in `find'", "/usr/local/bundle/ruby/3.2.0/gems/activerecord-8.0.2.1/lib/active_record/associations/collection_association.rb:113:in `find'", "/usr/local/bundle/ruby/3.2.0/gems/activerecord-8.0.2.1/lib/active_record/associations/collection_proxy.rb:140:in `find'", "/rails/app/controllers/project_settings_controller.rb:127:in `set_project'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:361:in `block in make_lambda'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:178:in `block in call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/abstract_controller/callbacks.rb:34:in `block (2 levels) in <module:Callbacks>'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:179:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:559:in `block in invoke_before'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:559:in `each'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:559:in `invoke_before'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:118:in `block in run_callbacks'", "/usr/local/bundle/ruby/3.2.0/gems/turbo-rails-2.0.16/lib/turbo-rails.rb:24:in `with_request_id'", "/usr/local/bundle/ruby/3.2.0/gems/turbo-rails-2.0.16/app/controllers/concerns/turbo/request_id_tracking.rb:10:in `turbo_tracking_request_id'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:129:in `block in run_callbacks'", "/usr/local/bundle/ruby/3.2.0/gems/actiontext-8.0.2.1/lib/action_text/rendering.rb:25:in `with_renderer'", "/usr/local/bundle/ruby/3.2.0/gems/actiontext-8.0.2.1/lib/action_text/engine.rb:71:in `block (4 levels) in <class:Engine>'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:129:in `instance_exec'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:129:in `block in run_callbacks'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:140:in `run_callbacks'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/abstract_controller/callbacks.rb:260:in `process_action'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_controller/metal/rescue.rb:27:in `process_action'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_controller/metal/instrumentation.rb:76:in `block in process_action'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/notifications.rb:210:in `block in instrument'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/notifications/instrumenter.rb:58:in `instrument'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/notifications.rb:210:in `instrument'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_controller/metal/instrumentation.rb:75:in `process_action'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_controller/metal/params_wrapper.rb:259:in `process_action'", "/usr/local/bundle/ruby/3.2.0/gems/activerecord-8.0.2.1/lib/active_record/railties/controller_runtime.rb:39:in `process_action'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/abstract_controller/base.rb:163:in `process'", "/usr/local/bundle/ruby/3.2.0/gems/actionview-8.0.2.1/lib/action_view/rendering.rb:40:in `process'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_controller/metal.rb:252:in `dispatch'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_controller/metal.rb:335:in `dispatch'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/routing/route_set.rb:67:in `dispatch'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/routing/route_set.rb:50:in `serve'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/journey/router.rb:53:in `block in serve'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/journey/router.rb:133:in `block in find_routes'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/journey/router.rb:126:in `each'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/journey/router.rb:126:in `find_routes'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/journey/router.rb:34:in `serve'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/routing/route_set.rb:908:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/omniauth-2.1.4/lib/omniauth/strategy.rb:202:in `call!'", "/usr/local/bundle/ruby/3.2.0/gems/omniauth-2.1.4/lib/omniauth/strategy.rb:169:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/omniauth-2.1.4/lib/omniauth/strategy.rb:202:in `call!'", "/usr/local/bundle/ruby/3.2.0/gems/omniauth-2.1.4/lib/omniauth/strategy.rb:169:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-attack-6.7.0/lib/rack/attack.rb:103:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-attack-6.7.0/lib/rack/attack.rb:127:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/warden-1.2.9/lib/warden/manager.rb:36:in `block in call'", "/usr/local/bundle/ruby/3.2.0/gems/warden-1.2.9/lib/warden/manager.rb:34:in `catch'", "/usr/local/bundle/ruby/3.2.0/gems/warden-1.2.9/lib/warden/manager.rb:34:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/tempfile_reaper.rb:20:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/etag.rb:29:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/conditional_get.rb:31:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/head.rb:15:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/http/permissions_policy.rb:38:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/http/content_security_policy.rb:38:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-session-2.1.1/lib/rack/session/abstract/id.rb:274:in `context'", "/usr/local/bundle/ruby/3.2.0/gems/rack-session-2.1.1/lib/rack/session/abstract/id.rb:268:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/cookies.rb:706:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/callbacks.rb:31:in `block in call'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/callbacks.rb:100:in `run_callbacks'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/callbacks.rb:30:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/activerabbit-ai-0.6.1/lib/active_rabbit/middleware/error_capture_middleware.rb:11:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/debug_exceptions.rb:31:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/show_exceptions.rb:32:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/railties-8.0.2.1/lib/rails/rack/logger.rb:41:in `call_app'", "/usr/local/bundle/ruby/3.2.0/gems/railties-8.0.2.1/lib/rails/rack/logger.rb:29:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/railties-8.0.2.1/lib/rails/rack/silence_request.rb:28:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/remote_ip.rb:96:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/request_id.rb:34:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/method_override.rb:28:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/runtime.rb:24:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/activesupport-8.0.2.1/lib/active_support/cache/strategy/local_cache_middleware.rb:29:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/executor.rb:16:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/static.rb:27:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/rack-3.2.0/lib/rack/sendfile.rb:114:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/actionpack-8.0.2.1/lib/action_dispatch/middleware/assume_ssl.rb:24:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/railties-8.0.2.1/lib/rails/engine.rb:535:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/configuration.rb:279:in `call'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/request.rb:99:in `block in handle_request'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/thread_pool.rb:390:in `with_force_shutdown'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/request.rb:98:in `handle_request'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/server.rb:472:in `process_client'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/server.rb:254:in `block in run'", "/usr/local/bundle/ruby/3.2.0/gems/puma-6.6.1/lib/puma/thread_pool.rb:167:in `block in spawn_thread'"]
```

**Request Context:**
- Method: `GET`
- Path: `/projects/1/settings`

## 🛡️ Prevention

- Use `find_by` instead of `find` when you want to handle cases where a record might not exist, allowing for custom error handling.
- Implement error handling for database queries to provide user-friendly feedback and prevent application crashes.
- Consider adding logging for failed lookups to monitor and address potential data integrity issues.

## ✅ Checklist

- [ ] Code fix implemented
- [ ] Tests added/updated
- [ ] Error scenario manually verified
- [ ] No regressions introduced

---
_Generated by [ActiveRabbit](https://activerabbit.ai) AI_

---
_Generated by [ActiveRabbit](https://activerabbit.ai) AI_