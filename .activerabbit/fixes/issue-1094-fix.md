# Fix for ActiveRecord::RecordNotFound

**Issue ID:** 1094
**Generated:** 2026-02-04 00:34 UTC
**Status:** 📋 Suggestion only (manual review required)

## Suggested Code Fix

```ruby
def set_company
  begin
    company_slug = ScraperCompany.friendly.find(params[:id]).slug
    @company = if root_domain?
      ScraperCompany.where(slug: company_slug, domain_id: nil).first
    else
      ScraperCompany.where(slug: company_slug, domain_id: @domain.id).first
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Company not found."
  end
end
```

## Full Analysis

## 🐛 Bug Fix: ActiveRecord::RecordNotFound

**Issue ID:** #1094
**Controller:** `CompaniesController#show`
**Occurrences:** 288063 times
**First seen:** 2026-01-08 05:32
**Last seen:** 2026-02-04 00:34

## 🔍 Root Cause Analysis

The error `ActiveRecord::RecordNotFound` occurs because the `ScraperCompany.friendly.find(params[:id])` call in the `set_company` method is unable to find a record with the friendly ID "ville-de-riviere-du-loup". This suggests that there is no `ScraperCompany` record with a slug matching this ID.

## 🔧 Suggested Fix

To fix this issue, you should handle the case where a record is not found and provide a user-friendly error message or redirect. Modify the `set_company` method to rescue the `ActiveRecord::RecordNotFound` exception:

### Before
```ruby
def set_company
  company_slug = ScraperCompany.friendly.find(params[:id]).slug
  @company = if root_domain?
    ScraperCompany.where(slug: company_slug, domain_id: nil).first
  else
    ScraperCompany.where(slug: company_slug, domain_id: @domain.id).first
  end
end
```

### After
```ruby
def set_company
  begin
    company_slug = ScraperCompany.friendly.find(params[:id]).slug
    @company = if root_domain?
      ScraperCompany.where(slug: company_slug, domain_id: nil).first
    else
      ScraperCompany.where(slug: company_slug, domain_id: @domain.id).first
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "Company not found."
  end
end
```

## 📋 Error Details

**Error Message:**
```
can't find record with friendly id: "ville-de-riviere-du-loup"
```

**Stack Trace (top frames):**
```
["/usr/local/bundle/ruby/3.1.0/gems/friendly_id-5.2.5/lib/friendly_id/finder_methods.rb:70:in `raise_not_found_exception'", "/usr/local/bundle/ruby/3.1.0/gems/friendly_id-5.2.5/lib/friendly_id/finder_methods.rb:23:in `find'", "/app/app/controllers/companies_controller.rb:198:in `set_company'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/callbacks.rb:427:in `block in make_lambda'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/callbacks.rb:179:in `block (2 levels) in halting_and_conditional'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/abstract_controller/callbacks.rb:34:in `block (2 levels) in <module:Callbacks>'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/callbacks.rb:180:in `block in halting_and_conditional'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/callbacks.rb:512:in `block in invoke_before'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/callbacks.rb:512:in `each'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/callbacks.rb:512:in `invoke_before'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/callbacks.rb:115:in `block in run_callbacks'", "/usr/local/bundle/ruby/3.1.0/gems/actiontext-6.1.7.8/lib/action_text/rendering.rb:20:in `with_renderer'", "/usr/local/bundle/ruby/3.1.0/gems/actiontext-6.1.7.8/lib/action_text/engine.rb:59:in `block (4 levels) in <class:Engine>'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/callbacks.rb:126:in `instance_exec'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/callbacks.rb:126:in `block in run_callbacks'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/callbacks.rb:137:in `run_callbacks'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/abstract_controller/callbacks.rb:41:in `process_action'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_controller/metal/rescue.rb:22:in `process_action'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_controller/metal/instrumentation.rb:34:in `block in process_action'", "/usr/local/bundle/ruby/3.1.0/gems/appsignal-3.10.0/lib/appsignal/hooks/active_support_notifications.rb:19:in `block in instrument'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/notifications/instrumenter.rb:24:in `instrument'", "/usr/local/bundle/ruby/3.1.0/gems/appsignal-3.10.0/lib/appsignal/hooks/active_support_notifications.rb:18:in `instrument'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_controller/metal/instrumentation.rb:33:in `process_action'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_controller/metal/params_wrapper.rb:249:in `process_action'", "/usr/local/bundle/ruby/3.1.0/gems/searchkick-5.3.1/lib/searchkick/controller_runtime.rb:15:in `process_action'", "/usr/local/bundle/ruby/3.1.0/gems/activerecord-6.1.7.8/lib/active_record/railties/controller_runtime.rb:27:in `process_action'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/abstract_controller/base.rb:165:in `process'", "/usr/local/bundle/ruby/3.1.0/gems/actionview-6.1.7.8/lib/action_view/rendering.rb:39:in `process'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_controller/metal.rb:190:in `dispatch'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_controller/metal.rb:254:in `dispatch'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/routing/route_set.rb:50:in `dispatch'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/routing/route_set.rb:33:in `serve'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/journey/router.rb:50:in `block in serve'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/journey/router.rb:32:in `each'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/journey/router.rb:32:in `serve'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/routing/route_set.rb:842:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/rack-attack-6.7.0/lib/rack/attack.rb:127:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/warden-1.2.9/lib/warden/manager.rb:36:in `block in call'", "/usr/local/bundle/ruby/3.1.0/gems/warden-1.2.9/lib/warden/manager.rb:34:in `catch'", "/usr/local/bundle/ruby/3.1.0/gems/warden-1.2.9/lib/warden/manager.rb:34:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/rack-2.2.9/lib/rack/tempfile_reaper.rb:15:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/rack-2.2.9/lib/rack/etag.rb:27:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/rack-2.2.9/lib/rack/conditional_get.rb:27:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/rack-2.2.9/lib/rack/head.rb:12:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/http/permissions_policy.rb:22:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/http/content_security_policy.rb:19:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/rack-2.2.9/lib/rack/session/abstract/id.rb:266:in `context'", "/usr/local/bundle/ruby/3.1.0/gems/rack-2.2.9/lib/rack/session/abstract/id.rb:260:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/middleware/cookies.rb:697:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/middleware/callbacks.rb:27:in `block in call'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/callbacks.rb:98:in `run_callbacks'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/middleware/callbacks.rb:26:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/middleware/actionable_exceptions.rb:18:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/appsignal-3.10.0/lib/appsignal/rack/abstract_middleware.rb:95:in `call_app'", "/usr/local/bundle/ruby/3.1.0/gems/appsignal-3.10.0/lib/appsignal/rack/abstract_middleware.rb:90:in `instrument_app_call'", "/usr/local/bundle/ruby/3.1.0/gems/appsignal-3.10.0/lib/appsignal/rack/abstract_middleware.rb:113:in `instrument_app_call_with_exception_handling'", "/usr/local/bundle/ruby/3.1.0/gems/appsignal-3.10.0/lib/appsignal/rack/abstract_middleware.rb:55:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/activerabbit-ai-0.6.1/lib/active_rabbit/middleware/error_capture_middleware.rb:11:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/middleware/debug_exceptions.rb:29:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/middleware/show_exceptions.rb:33:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/railties-6.1.7.8/lib/rails/rack/logger.rb:37:in `call_app'", "/usr/local/bundle/ruby/3.1.0/gems/railties-6.1.7.8/lib/rails/rack/logger.rb:26:in `block in call'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/tagged_logging.rb:99:in `block in tagged'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/tagged_logging.rb:37:in `tagged'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/tagged_logging.rb:99:in `tagged'", "/usr/local/bundle/ruby/3.1.0/gems/railties-6.1.7.8/lib/rails/rack/logger.rb:26:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/middleware/remote_ip.rb:81:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/middleware/request_id.rb:26:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/rack-2.2.9/lib/rack/method_override.rb:24:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/rack-2.2.9/lib/rack/deflater.rb:44:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/rack-2.2.9/lib/rack/runtime.rb:22:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/activesupport-6.1.7.8/lib/active_support/cache/strategy/local_cache_middleware.rb:29:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/middleware/executor.rb:14:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/middleware/static.rb:24:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/rack-2.2.9/lib/rack/sendfile.rb:110:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/middleware/ssl.rb:77:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/actionpack-6.1.7.8/lib/action_dispatch/middleware/host_authorization.rb:142:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/rack-2.2.9/lib/rack/events.rb:112:in `call'", "/app/config/initializers/redirect_www.rb:18:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/railties-6.1.7.8/lib/rails/engine.rb:539:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/puma-6.4.2/lib/puma/configuration.rb:272:in `call'", "/usr/local/bundle/ruby/3.1.0/gems/puma-6.4.2/lib/puma/request.rb:100:in `block in handle_request'", "/usr/local/bundle/ruby/3.1.0/gems/puma-6.4.2/lib/puma/thread_pool.rb:378:in `with_force_shutdown'", "/usr/local/bundle/ruby/3.1.0/gems/puma-6.4.2/lib/puma/request.rb:99:in `handle_request'", "/usr/local/bundle/ruby/3.1.0/gems/puma-6.4.2/lib/puma/server.rb:464:in `process_client'", "/usr/local/bundle/ruby/3.1.0/gems/puma-6.4.2/lib/puma/server.rb:245:in `block in run'", "/usr/local/bundle/ruby/3.1.0/gems/puma-6.4.2/lib/puma/thread_pool.rb:155:in `block in spawn_thread'"]
```

**Request Context:**
- Method: `GET`
- Path: `/company/canoo-inc`

## 🛡️ Prevention

- Ensure that all user inputs or parameters used to query the database are validated and sanitized.
- Implement error handling for database queries that might not return a result, using exceptions like `ActiveRecord::RecordNotFound`.
- Consider using logging to track when records are not found, which can help identify missing data or incorrect URLs.

## ✅ Checklist

- [ ] Code fix implemented
- [ ] Tests added/updated
- [ ] Error scenario manually verified
- [ ] No regressions introduced

---
_Generated by [ActiveRabbit](https://activerabbit.ai) AI_

---
_Generated by [ActiveRabbit](https://activerabbit.ai) AI_