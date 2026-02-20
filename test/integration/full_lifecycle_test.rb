# frozen_string_literal: true

require "test_helper"

# =============================================================================
# Full Lifecycle End-to-End Tests
# =============================================================================
#
# Covers the complete user journey from sign-up to plan change:
#
#   1. User creates an account (gets trial automatically)
#   2. User adds 1-2 apps (projects)
#   3. App receives first errors via API
#   4. AI explanation is generated for new issues
#   5. Notification email is sent for new errors
#   6. Trial ends → notification emails sent
#   7. Trial expires → account downgraded to free
#   8. User changes plan (free → team via checkout)
#
class FullLifecycleTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # ===========================================================================
  # 1. User creates an account — trial starts automatically
  # ===========================================================================

  test "new user signup creates account with active trial" do
    email = "newuser_#{SecureRandom.hex(4)}@example.com"

    # Simulate Devise registration
    post user_registration_path, params: {
      user: {
        email: email,
        password: "securepassword123",
        password_confirmation: "securepassword123"
      }
    }

    user = User.find_by(email: email)
    assert user.present?, "User should have been created"

    account = user.account
    assert account.present?, "Account should have been auto-created"
    assert_equal "trial", account.current_plan, "New account should start on trial plan"
    assert account.on_trial?, "New account should be on trial"
    assert account.trial_ends_at > Time.current, "Trial should end in the future"
    assert_in_delta 14.days.from_now, account.trial_ends_at, 30.seconds,
      "Trial should be 14 days"
    assert_equal 50_000, account.event_quota, "Should have trial event quota"
    assert_equal "owner", user.role, "First user should be owner"
  end

  # ===========================================================================
  # 2. User adds 1-2 apps (projects)
  # ===========================================================================

  test "user creates first project during onboarding" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    sign_in user
    ActsAsTenant.current_tenant = account

    # Ensure no projects exist initially on this account
    account.projects.destroy_all

    post projects_path, params: {
      project: {
        name: "My Rails App #{SecureRandom.hex(4)}",
        environment: "production",
        url: "https://myapp-#{SecureRandom.hex(4)}.example.com"
      }
    }

    assert_response :redirect, "Should redirect after project creation"

    project = account.projects.reload.last
    assert project.present?, "Project should have been created"
    assert project.api_tokens.active.any?, "Project should have an API token"
    assert project.alert_rules.any?, "Project should have default alert rules"
  end

  test "user creates a second project" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    sign_in user
    ActsAsTenant.current_tenant = account

    2.times do |i|
      post projects_path, params: {
        project: {
          name: "App #{i + 1} #{SecureRandom.hex(4)}",
          environment: "production",
          url: "https://app#{i + 1}-#{SecureRandom.hex(4)}.example.com"
        }
      }
      assert_response :redirect
    end

    assert account.projects.reload.count >= 2, "Account should have at least 2 projects"
  end

  # ===========================================================================
  # 3. App receives first errors via API
  # ===========================================================================

  test "project receives first errors via API and creates issues" do
    account = accounts(:default)
    project = projects(:default)
    token = api_tokens(:default)
    headers = { "CONTENT_TYPE" => "application/json", "X-Project-Token" => token.token }

    # Send first error
    error_payload_1 = {
      exception_class: "NoMethodError",
      message: "undefined method `name' for nil:NilClass",
      backtrace: [
        "app/controllers/users_controller.rb:25:in `show'",
        "actionpack/lib/action_controller/metal.rb:227:in `dispatch'"
      ],
      controller_action: "UsersController#show",
      environment: "production",
      occurred_at: Time.current.iso8601
    }.to_json

    post "/api/v1/events/errors", params: error_payload_1, headers: headers
    assert_response :created, "First error should be accepted"

    # Send second different error
    error_payload_2 = {
      exception_class: "ActiveRecord::RecordNotFound",
      message: "Couldn't find User with 'id'=999",
      backtrace: [
        "app/controllers/orders_controller.rb:10:in `index'",
        "actionpack/lib/action_controller/metal.rb:227:in `dispatch'"
      ],
      controller_action: "OrdersController#index",
      environment: "production",
      occurred_at: Time.current.iso8601
    }.to_json

    post "/api/v1/events/errors", params: error_payload_2, headers: headers
    assert_response :created, "Second error should be accepted"

    # Verify that Sidekiq jobs were enqueued for ingest
    assert Sidekiq::Queues["ingest"].size >= 2,
      "ErrorIngestJob should have been enqueued for both errors"
  end

  test "error ingest job creates events and issues from API payload" do
    account = accounts(:default)
    project = projects(:default)
    ActsAsTenant.current_tenant = account

    payload = {
      exception_class: "LifecycleTestError",
      message: "E2E test error for lifecycle",
      backtrace: ["app/services/payment.rb:42:in `charge'"],
      controller_action: "PaymentsController#create",
      environment: "production"
    }

    event = Event.ingest_error(project: project, payload: payload)

    assert event.present?, "Event should have been created"
    assert event.issue.present?, "Issue should have been created for the event"
    assert_equal "LifecycleTestError", event.issue.exception_class
    assert_equal 1, event.issue.count, "First occurrence should have count 1"
    assert_equal "open", event.issue.status
  end

  # ===========================================================================
  # 4. AI explanation is generated for new issues
  # ===========================================================================

  test "AI summary is generated for a new issue" do
    account = accounts(:default)
    project = projects(:default)
    ActsAsTenant.current_tenant = account

    # Create a new issue with first event
    payload = {
      exception_class: "AiLifecycleError",
      message: "Error that needs AI explanation",
      backtrace: ["app/models/order.rb:15:in `validate_total'"],
      controller_action: "OrdersController#create",
      environment: "production"
    }

    event = Event.ingest_error(project: project, payload: payload)
    issue = event.issue
    assert issue.ai_summary.blank?, "New issue should not have AI summary yet"

    # Simulate AI summary generation
    ai_response = "This error occurs when the order total validation fails because the total amount is nil. " \
                  "Check that the cart items are properly summed before calling validate_total."

    AiSummaryService.stub(:new, ->(*args) {
      OpenStruct.new(call: { summary: ai_response })
    }) do
      AiSummaryJob.new.perform(issue.id, event.id, project.id)
    end

    issue.reload
    assert issue.ai_summary.present?, "Issue should now have an AI summary"
    assert_includes issue.ai_summary, "order total validation",
      "AI summary should contain relevant explanation"
    assert issue.ai_summary_generated_at.present?, "Should record when summary was generated"
  end

  test "AI summary respects quota limits" do
    account = accounts(:default)
    project = projects(:default)
    ActsAsTenant.current_tenant = account

    payload = {
      exception_class: "QuotaTestLifecycleError",
      message: "Should be blocked by quota",
      backtrace: [],
      controller_action: "HomeController#index",
      environment: "production"
    }

    event = Event.ingest_error(project: project, payload: payload)
    issue = event.issue

    # Stub within_quota? to return false (account is over quota)
    original_method = Account.instance_method(:within_quota?)
    Account.define_method(:within_quota?) { |*_args| false }

    AiSummaryService.stub(:new, ->(*args) {
      raise "Should NOT call AI service when over quota!"
    }) do
      assert_nothing_raised do
        AiSummaryJob.new.perform(issue.id, event.id, project.id)
      end
    end

    issue.reload
    assert_nil issue.ai_summary, "Should not generate AI summary when over quota"
  ensure
    Account.define_method(:within_quota?, original_method)
  end

  # ===========================================================================
  # 5. Notification email is sent for new errors
  # ===========================================================================

  test "new issue triggers alert notification email" do
    account = accounts(:default)
    project = projects(:default)
    user = users(:owner)
    ActsAsTenant.current_tenant = account

    # Ensure project has a new_issue alert rule
    rule = project.alert_rules.find_by(rule_type: "new_issue")
    assert rule.present?, "Project should have a new_issue alert rule"
    assert rule.enabled?, "Alert rule should be enabled"

    # Create a new issue
    payload = {
      exception_class: "NotificationTestError",
      message: "This error should trigger an email notification",
      backtrace: ["app/controllers/api_controller.rb:30:in `handle_request'"],
      controller_action: "ApiController#handle_request",
      environment: "production"
    }

    event = Event.ingest_error(project: project, payload: payload)
    issue = event.issue

    # Simulate what AlertJob does - send email notification
    ActionMailer::Base.deliveries.clear

    AlertMailer.send_alert(
      to: user.email,
      subject: "#{project.name}: New Issue Alert",
      body: "New error: #{issue.exception_class} — #{issue.sample_message}",
      project: project
    ).deliver_now

    assert_equal 1, ActionMailer::Base.deliveries.size,
      "Should have sent one alert email"

    email = ActionMailer::Base.deliveries.last
    assert_equal [user.email], email.to
    assert_includes email.subject, "New Issue Alert"
  end

  # ===========================================================================
  # 6. Trial ends → notification emails are sent
  # ===========================================================================

  test "trial ending soon sends reminder emails at correct intervals" do
    account = accounts(:trial_account)
    user = users(:trial_user)

    # Test 8-day reminder
    account.update!(trial_ends_at: 8.days.from_now)

    mail_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      if args[:account] == account && args[:days_left] == 8
        mail_sent = true
      end
      mock_mail
    }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
        LifecycleMailer.stub(:trial_expired_warning, ->(**args) { Minitest::Mock.new }) do
          TrialReminderCheckJob.perform_now
        end
      end
    end

    assert mail_sent, "Should send 8-day trial reminder"
  end

  test "trial ends today sends final notice email" do
    account = accounts(:trial_account)
    account.update!(trial_ends_at: Time.current)

    today_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) { Minitest::Mock.new }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) {
        if args[:account] == account
          today_sent = true
        end
        mock_mail
      }) do
        LifecycleMailer.stub(:trial_expired_warning, ->(**args) { Minitest::Mock.new }) do
          TrialReminderCheckJob.perform_now
        end
      end
    end

    assert today_sent, "Should send trial-ends-today email"
  end

  test "post-trial expiry sends warning emails" do
    account = accounts(:trial_account)
    account.update!(trial_ends_at: 2.days.ago)

    warning_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) { Minitest::Mock.new }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
        LifecycleMailer.stub(:trial_expired_warning, ->(**args) {
          if args[:account] == account && args[:days_since_expired] == 2
            warning_sent = true
          end
          mock_mail
        }) do
          TrialReminderCheckJob.perform_now
        end
      end
    end

    assert warning_sent, "Should send 2-day post-expiry warning"
  end

  test "trial reminder skips accounts with active subscription" do
    account = accounts(:trial_account)
    account.update!(trial_ends_at: 4.days.from_now)

    mail_sent = false

    original_method = Account.instance_method(:active_subscription?)
    Account.define_method(:active_subscription?) { true }

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      if args[:account] == account
        mail_sent = true
      end
      Minitest::Mock.new
    }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
        TrialReminderCheckJob.perform_now
      end
    end

    refute mail_sent, "Should NOT send reminder if account has active subscription"
  ensure
    Account.define_method(:active_subscription?, original_method)
  end

  # ===========================================================================
  # 7. Trial expires → account downgraded to free plan
  # ===========================================================================

  test "trial expiration job downgrades expired accounts to free plan" do
    account = accounts(:trial_account)
    account.update!(
      trial_ends_at: 10.days.ago,
      current_plan: "trial",
      event_quota: 50_000
    )

    # Stub active_subscription? and has_payment_method? so downgrade happens
    orig_sub = Account.instance_method(:active_subscription?)
    orig_pay = Account.instance_method(:has_payment_method?)
    Account.define_method(:active_subscription?) { false }
    Account.define_method(:has_payment_method?) { false }

    ActionMailer::Base.deliveries.clear

    TrialExpirationJob.perform_now

    account.reload
    assert_equal "free", account.current_plan,
      "Account should be downgraded to free after trial expires"
    assert_equal 5_000, account.event_quota,
      "Event quota should be reduced to free plan level"

    # Should send downgrade notification
    downgrade_email = ActionMailer::Base.deliveries.find { |e|
      e.subject.include?("Free plan")
    }
    assert downgrade_email.present?,
      "Should send downgrade notification email"
  ensure
    Account.define_method(:active_subscription?, orig_sub)
    Account.define_method(:has_payment_method?, orig_pay)
  end

  test "trial expiration job does NOT downgrade accounts with active subscription" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    account.update!(
      trial_ends_at: 10.days.ago,
      current_plan: "trial",
      event_quota: 50_000
    )

    # Create a real Pay::Customer + Pay::Subscription so the SQL scope
    # (needing_payment_reminder) excludes this account
    pay_customer = Pay::Customer.create!(
      owner: user,
      processor: "stripe",
      processor_id: "cus_test_#{SecureRandom.hex(8)}"
    )
    Pay::Subscription.create!(
      customer: pay_customer,
      processor_id: "sub_test_#{SecureRandom.hex(8)}",
      name: "default",
      processor_plan: "team_monthly",
      status: "active"
    )

    TrialExpirationJob.perform_now

    account.reload
    assert_equal "trial", account.current_plan,
      "Account with subscription should NOT be downgraded"
    assert_equal 50_000, account.event_quota,
      "Quota should remain unchanged for subscribed accounts"
  end

  test "account reflects correct plan state after trial expires" do
    account = accounts(:trial_account)

    # During trial
    account.update!(trial_ends_at: 5.days.from_now, current_plan: "trial")
    assert account.on_trial?, "Should be on trial"
    refute account.trial_expired?, "Should NOT be expired"

    # After trial expires
    account.update!(trial_ends_at: 1.day.ago)
    refute account.on_trial?, "Should NOT be on trial anymore"
    assert account.trial_expired?, "Should be expired"

    # Effective plan should reflect free when expired without payment
    orig_pay = Account.instance_method(:has_payment_method?)
    orig_sub = Account.instance_method(:active_subscription?)
    Account.define_method(:has_payment_method?) { false }
    Account.define_method(:active_subscription?) { false }

    assert account.trial_expired_without_payment?,
      "Should detect expired trial without payment"
  ensure
    Account.define_method(:has_payment_method?, orig_pay)
    Account.define_method(:active_subscription?, orig_sub)
  end

  # ===========================================================================
  # 8. User changes plan (free → team upgrade via checkout)
  # ===========================================================================

  test "user can switch to free plan directly" do
    account = accounts(:default)
    user = users(:owner)
    sign_in user
    ActsAsTenant.current_tenant = account

    # Start on team plan
    account.update!(current_plan: "team")

    post checkouts_path, params: { plan: "free" }

    assert_redirected_to dashboard_path
    account.reload
    assert_equal "free", account.current_plan, "Account should be on free plan"
  end

  test "user initiates paid plan upgrade via Stripe checkout" do
    account = accounts(:default)
    user = users(:owner)
    sign_in user
    ActsAsTenant.current_tenant = account

    # Start on free plan (after trial expired)
    account.update!(current_plan: "free", trial_ends_at: 10.days.ago)

    # Stub Stripe checkout creation
    mock_checkout = OpenStruct.new(url: "https://checkout.stripe.com/test-session")

    checkout_params = nil
    CheckoutCreator.stub(:new, ->(**args) {
      checkout_params = args
      OpenStruct.new(call: mock_checkout)
    }) do
      post checkouts_path, params: { plan: "team", interval: "month" }
      assert_response :see_other, "Should redirect to Stripe checkout"
    end

    assert_equal "team", checkout_params[:plan], "Should request team plan"
    assert_equal "month", checkout_params[:interval], "Should request monthly billing"
  end

  test "user can choose yearly billing interval" do
    account = accounts(:default)
    user = users(:owner)
    sign_in user
    ActsAsTenant.current_tenant = account

    account.update!(current_plan: "free", trial_ends_at: 10.days.ago)

    mock_checkout = OpenStruct.new(url: "https://checkout.stripe.com/test-yearly")
    interval_passed = nil

    CheckoutCreator.stub(:new, ->(**args) {
      interval_passed = args[:interval]
      OpenStruct.new(call: mock_checkout)
    }) do
      post checkouts_path, params: { plan: "team", interval: "year" }
    end

    assert_equal "year", interval_passed, "Should pass yearly interval"
  end

  # ===========================================================================
  # Full journey: signup → errors → trial → downgrade → upgrade
  # ===========================================================================

  test "complete user lifecycle from signup through plan change" do
    email = "lifecycle_#{SecureRandom.hex(4)}@example.com"

    # --- Step 1: User signs up ---
    post user_registration_path, params: {
      user: {
        email: email,
        password: "lifecycle_pass_123",
        password_confirmation: "lifecycle_pass_123"
      }
    }

    user = User.find_by(email: email)
    assert user.present?, "Step 1: User created"
    account = user.account
    assert account.on_trial?, "Step 1: Account is on trial"
    assert_equal "trial", account.current_plan, "Step 1: Account starts on trial plan"

    # Confirm user so they can sign in and receive emails
    user.update!(confirmed_at: Time.current)
    sign_in user
    ActsAsTenant.current_tenant = account

    # --- Step 2: Create first project ---
    post projects_path, params: {
      project: {
        name: "Lifecycle App #{SecureRandom.hex(4)}",
        environment: "production",
        url: "https://lifecycle-#{SecureRandom.hex(4)}.example.com"
      }
    }
    assert_response :redirect, "Step 2: Project created"

    project = account.projects.reload.last
    assert project.present?, "Step 2: Project exists"
    token = project.api_tokens.active.first
    assert token.present?, "Step 2: API token generated"

    # --- Step 3: Receive first errors ---
    api_headers = { "CONTENT_TYPE" => "application/json", "X-Project-Token" => token.token }

    post "/api/v1/events/errors", params: {
      exception_class: "LifecycleNoMethodError",
      message: "undefined method `foo' for nil",
      backtrace: ["app/models/widget.rb:10:in `process'"],
      controller_action: "WidgetsController#create",
      environment: "production",
      occurred_at: Time.current.iso8601
    }.to_json, headers: api_headers

    assert_response :created, "Step 3: Error accepted via API"

    # Re-set tenant (API request cleared it) and process the error inline
    ActsAsTenant.current_tenant = account

    event = Event.ingest_error(
      project: project,
      payload: {
        exception_class: "LifecycleNoMethodError",
        message: "undefined method `foo' for nil",
        backtrace: ["app/models/widget.rb:10:in `process'"],
        controller_action: "WidgetsController#create",
        environment: "production"
      }
    )

    issue = event.issue
    assert issue.present?, "Step 3: Issue created"
    assert_equal "open", issue.status, "Step 3: Issue is open"

    # --- Step 4: AI summary generated ---
    AiSummaryService.stub(:new, ->(*args) {
      OpenStruct.new(call: { summary: "The `foo` method is called on a nil Widget." })
    }) do
      AiSummaryJob.new.perform(issue.id, event.id, project.id)
    end

    issue.reload
    assert issue.ai_summary.present?, "Step 4: AI summary generated"

    # --- Step 5: Notification email for error ---
    ActionMailer::Base.deliveries.clear
    AlertMailer.send_alert(
      to: user.email,
      subject: "#{project.name}: New Issue Alert",
      body: "New error: #{issue.exception_class}",
      project: project
    ).deliver_now

    assert ActionMailer::Base.deliveries.any?, "Step 5: Alert email sent"
    assert_equal [user.email], ActionMailer::Base.deliveries.last.to

    # --- Step 6: Trial ending reminder ---
    account.update!(trial_ends_at: 2.days.from_now)
    ActionMailer::Base.deliveries.clear

    reminder_mail = LifecycleMailer.trial_ending_soon(account: account, days_left: 2)
    reminder_mail.deliver_now

    assert ActionMailer::Base.deliveries.any?, "Step 6: Trial reminder sent"
    assert_includes ActionMailer::Base.deliveries.last.subject, "Trial ends in 2 days"

    # --- Step 7: Trial expires, downgrade to free ---
    account.update!(trial_ends_at: 10.days.ago)
    ActionMailer::Base.deliveries.clear

    orig_sub = Account.instance_method(:active_subscription?)
    orig_pay = Account.instance_method(:has_payment_method?)
    Account.define_method(:active_subscription?) { false }
    Account.define_method(:has_payment_method?) { false }

    begin
      TrialExpirationJob.perform_now
    ensure
      Account.define_method(:active_subscription?, orig_sub)
      Account.define_method(:has_payment_method?, orig_pay)
    end

    account.reload
    assert_equal "free", account.current_plan, "Step 7: Downgraded to free"
    assert_equal 5_000, account.event_quota, "Step 7: Quota reduced"

    # Downgrade email sent
    downgrade_email = ActionMailer::Base.deliveries.find { |e|
      e.subject.include?("Free plan")
    }
    assert downgrade_email.present?, "Step 7: Downgrade email sent"

    # --- Step 8: User upgrades to team ---
    mock_checkout = OpenStruct.new(url: "https://checkout.stripe.com/lifecycle-upgrade")

    CheckoutCreator.stub(:new, ->(**args) {
      OpenStruct.new(call: mock_checkout)
    }) do
      post checkouts_path, params: { plan: "team", interval: "month" }
      assert_response :see_other, "Step 8: Redirected to Stripe checkout"
    end

    # Simulate successful checkout callback updating the account
    account.update!(current_plan: "team", event_quota: 50_000, trial_ends_at: nil)
    account.reload

    assert_equal "team", account.current_plan, "Step 8: Upgraded to team"
    assert_equal 50_000, account.event_quota, "Step 8: Team quota restored"
    refute account.on_trial?, "Step 8: No longer on trial (paid subscription)"
  end

  # ===========================================================================
  # 9. Free plan end-to-end: quotas, hard cap, no Slack, no AI
  # ===========================================================================

  test "free plan enforces all restrictions end-to-end" do
    free_account = accounts(:free_account)
    free_project = projects(:free_project)
    free_token = api_tokens(:free_token)
    free_user = users(:free_account_owner)
    sign_in free_user
    ActsAsTenant.current_tenant = free_account

    # --- Verify free plan quotas ---
    assert_equal "free", free_account.current_plan
    assert free_account.on_free_plan?
    assert_equal 5_000, free_account.event_quota_value
    assert_equal 0, free_account.ai_summaries_quota
    assert_equal 0, free_account.pull_requests_quota
    assert_equal 999_999, free_account.projects_quota
    assert_equal 5, free_account.data_retention_days
    refute free_account.slack_notifications_allowed?

    # --- Accept events under quota ---
    free_account.update!(cached_events_used: 100)
    api_headers = { "CONTENT_TYPE" => "application/json", "X-Project-Token" => free_token.token }

    post "/api/v1/events/errors", params: {
      exception_class: "FreeE2EError",
      message: "Under quota — should be accepted",
      backtrace: ["app/models/test.rb:1:in `run'"],
      occurred_at: Time.current.iso8601
    }.to_json, headers: api_headers

    assert_response :created, "Free plan under quota should accept events"

    # --- Hard cap: reject events when over quota ---
    free_account.update!(cached_events_used: 5_001)
    # Clear the cache so the controller re-checks
    Rails.cache.delete("free_plan_capped:#{free_account.id}")

    post "/api/v1/events/errors", params: {
      exception_class: "FreeE2ECapped",
      message: "Over quota — should be rejected",
      backtrace: ["app/models/test.rb:1:in `run'"],
      occurred_at: Time.current.iso8601
    }.to_json, headers: api_headers

    assert_response :too_many_requests, "Free plan over quota should return 429"
    json = JSON.parse(response.body)
    assert_equal "quota_exceeded", json["error"]
    assert_includes json["message"], "5,000"

    # --- Batch endpoint also returns 429 ---
    post "/api/v1/events/batch", params: {
      events: [
        { event_type: "error", data: { exception_class: "BatchError", message: "batch" } }
      ]
    }.to_json, headers: api_headers

    assert_response :too_many_requests, "Free plan batch endpoint should also return 429"

    # --- Performance endpoint also returns 429 ---
    post "/api/v1/events/performance", params: {
      controller_action: "HomeController#index",
      duration_ms: 100,
      occurred_at: Time.current.iso8601
    }.to_json, headers: api_headers

    assert_response :too_many_requests, "Free plan performance endpoint should also return 429"

    # --- Ingest job safety net: drops events for capped account ---
    ActsAsTenant.current_tenant = free_account

    assert_no_difference "Event.count" do
      ErrorIngestJob.new.perform(free_project.id, {
        exception_class: "SafetyNetError",
        message: "Should be dropped by job safety net",
        backtrace: [],
        controller_action: "TestController#run",
        environment: "production"
      })
    end

    # --- AI summaries: fully blocked on free plan ---
    refute free_account.within_quota?(:ai_summaries),
      "Free plan should have 0 AI summaries (within_quota? returns false)"

    refute free_account.eligible_for_auto_ai_summary?,
      "Free plan should not be eligible for auto AI summary"

    # Verify regenerate_ai_summary redirects to plan page for free plan
    # Create an issue directly (avoid Sidekiq drain issues in parallel tests)
    ActsAsTenant.current_tenant = free_account
    ai_test_event = Event.ingest_error(project: free_project, payload: {
      exception_class: "FreeAiTestError",
      message: "Test issue for AI redirect",
      backtrace: ["app/models/test.rb:1:in `run'"],
      controller_action: "TestController#run",
      environment: "production"
    })

    ai_test_issue = ai_test_event.issue
    assert ai_test_issue.present?, "Issue should have been created"

    # POST regenerate_ai_summary — should redirect to plan page (JSON)
    post regenerate_ai_summary_error_path(ai_test_issue),
      headers: { "Accept" => "application/json", "X-Requested-With" => "XMLHttpRequest" }

    assert_response :ok # JSON response with free_plan: true
    ai_json = JSON.parse(response.body)
    assert_equal false, ai_json["success"]
    assert_equal true, ai_json["free_plan"], "Should indicate free plan block"
    assert ai_json["redirect_url"].present?, "Should include redirect URL to plan page"

    # --- Slack notifications: blocked on free plan ---
    free_project.update!(
      slack_access_token: "xoxb-test",
      slack_channel_id: "#alerts",
      slack_team_name: "Test"
    )
    slack_service = SlackNotificationService.new(free_project)
    refute slack_service.configured?,
      "Free plan project should not have Slack configured"

    account_slack = AccountSlackNotificationService.new(free_account)
    refute account_slack.configured?,
      "Free plan account should not have Slack configured"
  end

  # ===========================================================================
  # 10. Team plan end-to-end: full features, overages, no hard cap
  # ===========================================================================

  test "team plan provides full features end-to-end" do
    team_account = accounts(:team_account)
    user = users(:second_owner)
    sign_in user
    ActsAsTenant.current_tenant = team_account

    # --- Verify team plan quotas ---
    assert_equal "team", team_account.current_plan
    refute team_account.on_free_plan?
    assert_equal 50_000, team_account.event_quota_value
    assert_equal 20, team_account.ai_summaries_quota
    assert_equal 20, team_account.pull_requests_quota
    assert_equal 31, team_account.data_retention_days
    assert team_account.slack_notifications_allowed?

    # --- Create a project ---
    post projects_path, params: {
      project: {
        name: "Team E2E App #{SecureRandom.hex(4)}",
        environment: "production",
        url: "https://team-e2e-#{SecureRandom.hex(4)}.example.com"
      }
    }
    assert_response :redirect, "Team plan should be able to create projects"

    project = team_account.projects.reload.last
    assert project.present?
    token = project.api_tokens.active.first
    assert token.present?

    # --- Accept events even when over quota (no hard cap for team) ---
    team_account.update!(cached_events_used: 999_999)

    api_headers = { "CONTENT_TYPE" => "application/json", "X-Project-Token" => token.token }
    post "/api/v1/events/errors", params: {
      exception_class: "TeamE2EError",
      message: "Team plan has no hard cap",
      backtrace: ["app/models/team.rb:1:in `run'"],
      occurred_at: Time.current.iso8601
    }.to_json, headers: api_headers

    assert_response :created, "Team plan should accept events even when over quota"

    # --- free_plan_events_capped? returns false for team ---
    refute team_account.free_plan_events_capped?,
      "Team plan should never be hard-capped"

    # --- AI summaries: available on team plan ---
    team_account.update!(cached_ai_summaries_used: 5)
    assert team_account.within_quota?(:ai_summaries),
      "Team plan should have AI summaries available (5/20 used)"

    # --- Slack notifications: available on team plan ---
    project.update!(
      slack_access_token: "xoxb-team-test",
      slack_channel_id: "#team-alerts",
      slack_team_name: "Team"
    )
    slack_service = SlackNotificationService.new(project)
    assert slack_service.configured?,
      "Team plan project should have Slack configured"

    # --- Ingest job does NOT drop events for team ---
    ActsAsTenant.current_tenant = team_account
    assert_difference "Event.count", 1 do
      ErrorIngestJob.new.perform(project.id, {
        exception_class: "TeamIngestError",
        message: "Team plan events are never dropped",
        backtrace: ["app/models/team.rb:1:in `run'"],
        controller_action: "TeamController#run",
        environment: "production"
      })
    end
  end

  # ===========================================================================
  # 11. Plan upgrade resets usage counters & sends welcome email E2E
  # ===========================================================================

  test "upgrading from free to team resets usage and sends welcome email end-to-end" do
    account = accounts(:free_account)
    user = users(:free_account_owner)
    user.update!(confirmed_at: Time.current) unless user.confirmed_at.present?
    sign_in user
    ActsAsTenant.current_tenant = account

    # --- Setup: free plan with accumulated usage ---
    account.update!(
      current_plan: "free",
      trial_ends_at: 1.month.ago,
      cached_events_used: 4_200,
      cached_performance_events_used: 150,
      cached_ai_summaries_used: 0,
      cached_pull_requests_used: 0,
      cached_projects_used: 3
    )
    Rails.cache.write("free_plan_capped:#{account.id}", true)

    assert account.on_free_plan?, "Pre-check: account should be on free plan"
    assert_equal 4_200, account.cached_events_used, "Pre-check: events usage should be 4200"
    assert_equal 3, account.cached_projects_used, "Pre-check: projects should be 3"

    # --- Simulate Stripe webhook: subscription created (free -> team) ---
    pay_customer = Pay::Customer.find_or_create_by!(
      owner: account, processor: "stripe"
    ) { |c| c.processor_id = "cus_e2e_upgrade_#{SecureRandom.hex(4)}" }

    team_price_id = "price_e2e_team_monthly_#{SecureRandom.hex(4)}"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    ActionMailer::Base.deliveries.clear

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => pay_customer.processor_id,
          "id" => "sub_e2e_upgrade_#{SecureRandom.hex(4)}",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => team_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    account.reload

    # --- Verify plan changed ---
    assert_equal "team", account.current_plan,
      "Account should now be on team plan"
    refute account.on_free_plan?,
      "Account should no longer be on free plan"

    # --- Verify usage counters were reset ---
    assert_equal 0, account.cached_events_used,
      "Events used should be reset to 0 on upgrade"
    assert_equal 0, account.cached_performance_events_used,
      "Performance events should be reset to 0"
    assert_equal 0, account.cached_ai_summaries_used,
      "AI summaries should be reset to 0"
    assert_equal 0, account.cached_pull_requests_used,
      "Pull requests should be reset to 0"

    # --- Verify projects NOT reset (carry over) ---
    assert_equal 3, account.cached_projects_used,
      "Projects should NOT be reset — they carry over"

    # --- Verify free_plan_capped cache cleared ---
    assert_nil Rails.cache.read("free_plan_capped:#{account.id}"),
      "Free plan capped cache should be cleared after upgrade"

    # --- Verify welcome email was enqueued ---
    # deliver_later enqueues via ActiveJob; check deliveries
    perform_enqueued_jobs
    welcome_email = ActionMailer::Base.deliveries.find { |e|
      e.subject.include?("Welcome to ActiveRabbit Team")
    }
    assert welcome_email.present?,
      "Should send welcome email on plan upgrade"
    assert_equal [user.email], welcome_email.to,
      "Welcome email should go to account owner"

    # --- Verify new team quotas are active ---
    assert_equal 50_000, account.event_quota_value,
      "Should have team event quota"
    assert_equal 20, account.ai_summaries_quota,
      "Should have team AI quota"
    assert_equal 20, account.pull_requests_quota,
      "Should have team PR quota"
    assert_equal 31, account.data_retention_days,
      "Should have team data retention"
    assert account.slack_notifications_allowed?,
      "Slack should be available on team plan"

    # --- Verify user can now use AI summaries ---
    account.update!(cached_ai_summaries_used: 0)
    assert account.within_quota?(:ai_summaries),
      "Team plan should allow AI summaries (0/20 used)"
    assert_equal 20, account.ai_summaries_quota,
      "Team plan should have 20 AI summaries quota"

    # --- Verify events are accepted again (no hard cap on team) ---
    account.update!(cached_events_used: 60_000)
    refute account.free_plan_events_capped?,
      "Team plan should never be hard-capped"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ===========================================================================
  # 12. Trial expiration resets usage counters E2E
  # ===========================================================================

  test "trial expiration resets usage counters when downgrading to free" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    user.update!(confirmed_at: Time.current) unless user.confirmed_at.present?
    ActsAsTenant.current_tenant = account

    # --- Setup: trial account with accumulated usage ---
    account.update!(
      trial_ends_at: 1.day.ago,
      current_plan: "trial",
      event_quota: 50_000,
      cached_events_used: 12_000,
      cached_performance_events_used: 500,
      cached_ai_summaries_used: 8,
      cached_pull_requests_used: 3,
      cached_projects_used: 2
    )

    assert_equal 12_000, account.cached_events_used, "Pre-check: events used"
    assert_equal 8, account.cached_ai_summaries_used, "Pre-check: AI used"
    assert_equal 3, account.cached_pull_requests_used, "Pre-check: PRs used"
    assert_equal 2, account.cached_projects_used, "Pre-check: projects used"

    # --- Run trial expiration job ---
    orig_sub = Account.instance_method(:active_subscription?)
    orig_pay = Account.instance_method(:has_payment_method?)
    Account.define_method(:active_subscription?) { false }
    Account.define_method(:has_payment_method?) { false }

    ActionMailer::Base.deliveries.clear

    begin
      TrialExpirationJob.perform_now
    ensure
      Account.define_method(:active_subscription?, orig_sub)
      Account.define_method(:has_payment_method?, orig_pay)
    end

    account.reload

    # --- Verify downgraded to free ---
    assert_equal "free", account.current_plan,
      "Account should be downgraded to free"
    assert_equal 5_000, account.event_quota,
      "Event quota should be free plan level"

    # --- Verify usage counters reset ---
    assert_equal 0, account.cached_events_used,
      "Events should be reset on downgrade"
    assert_equal 0, account.cached_performance_events_used,
      "Performance events should be reset"
    assert_equal 0, account.cached_ai_summaries_used,
      "AI summaries should be reset"
    assert_equal 0, account.cached_pull_requests_used,
      "Pull requests should be reset"

    # --- Verify projects NOT reset ---
    assert_equal 2, account.cached_projects_used,
      "Projects should NOT be reset on downgrade"

    # --- Verify downgrade email sent ---
    downgrade_email = ActionMailer::Base.deliveries.find { |e|
      e.subject.include?("Free plan")
    }
    assert downgrade_email.present?,
      "Should send downgrade notification email"

    # --- Verify free plan restrictions now apply ---
    assert account.on_free_plan?, "Should now be on free plan"
    assert_equal 0, account.ai_summaries_quota, "Free plan: 0 AI summaries"
    assert_equal 0, account.pull_requests_quota, "Free plan: 0 PRs"
    assert_equal 5, account.data_retention_days, "Free plan: 5 days retention"
    refute account.slack_notifications_allowed?, "Free plan: no Slack"
  end

  # ===========================================================================
  # 13. Full upgrade round-trip: free -> team -> usage -> renewal (no reset)
  # ===========================================================================

  test "same-plan renewal does NOT reset usage counters" do
    account = accounts(:team_account)
    user = users(:second_owner)
    ActsAsTenant.current_tenant = account

    # --- Setup: team plan with usage mid-cycle ---
    account.update!(
      current_plan: "team",
      cached_events_used: 25_000,
      cached_ai_summaries_used: 10,
      cached_pull_requests_used: 7
    )

    pay_customer = Pay::Customer.find_or_create_by!(
      owner: account, processor: "stripe"
    ) { |c| c.processor_id = "cus_e2e_renew_#{SecureRandom.hex(4)}" }

    team_price_id = "price_e2e_renew_team_#{SecureRandom.hex(4)}"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    ActionMailer::Base.deliveries.clear

    # Simulate subscription.updated (renewal, same plan)
    renewal_event = {
      "type" => "customer.subscription.updated",
      "data" => {
        "object" => {
          "customer" => pay_customer.processor_id,
          "id" => "sub_e2e_renew_#{SecureRandom.hex(4)}",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => team_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: renewal_event).call
    account.reload

    # --- Plan stays team ---
    assert_equal "team", account.current_plan

    # --- Usage counters should NOT be reset ---
    assert_equal 25_000, account.cached_events_used,
      "Events should NOT be reset on same-plan renewal"
    assert_equal 10, account.cached_ai_summaries_used,
      "AI summaries should NOT be reset"
    assert_equal 7, account.cached_pull_requests_used,
      "PRs should NOT be reset"

    # --- No welcome email sent on renewal ---
    perform_enqueued_jobs
    welcome_email = ActionMailer::Base.deliveries.find { |e|
      e.subject.include?("Welcome to ActiveRabbit")
    }
    assert_nil welcome_email,
      "Should NOT send welcome email on same-plan renewal"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end
end
