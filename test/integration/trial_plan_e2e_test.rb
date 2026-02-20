# frozen_string_literal: true

require "test_helper"

# =============================================================================
# Trial Plan End-to-End Tests
# =============================================================================
#
# Covers the complete trial plan lifecycle introduced to replace the
# "start on team plan" approach:
#
#   1. Signup → trial plan with team-level quotas for 14 days
#   2. Trial quotas: events, AI summaries, Slack, data retention
#   3. Incomplete Stripe subscription does NOT upgrade plan
#   4. Past-due Stripe subscription does NOT upgrade plan
#   5. Active Stripe subscription upgrades trial → team
#   6. Trial expiration without payment → downgrade to free
#   7. Trial reminders sent at correct intervals
#   8. Data retention treats expired trials as free-tier
#   9. Full journey: signup → trial → incomplete checkout → pay → team
#  10. Full journey: signup → trial → expire → free → upgrade → team
#
class TrialPlanE2eTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # ===========================================================================
  # 1. Signup creates account on trial plan (not team)
  # ===========================================================================

  test "signup creates account on trial plan with 14-day window" do
    email = "trial_e2e_#{SecureRandom.hex(4)}@example.com"

    post user_registration_path, params: {
      user: {
        email: email,
        password: "securepassword123",
        password_confirmation: "securepassword123"
      }
    }

    user = User.find_by(email: email)
    assert user.present?, "User should be created"

    account = user.account
    assert_equal "trial", account.current_plan
    assert account.on_trial?
    assert_equal 50_000, account.event_quota
    assert_in_delta 14.days.from_now, account.trial_ends_at, 30.seconds
    refute account.trial_expired?
  end

  # ===========================================================================
  # 2. Trial plan provides team-level quotas during the 14-day window
  # ===========================================================================

  test "trial plan provides team-level quotas" do
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 7.days.from_now)

    assert account.on_trial?
    assert_equal :trial, account.send(:effective_plan_key)
    assert_equal "Free Trial", account.effective_plan_name
    assert_equal 50_000, account.event_quota_value
    assert_equal 20, account.ai_summaries_quota
    assert_equal 31, account.data_retention_days
    assert account.slack_notifications_allowed?
    refute account.on_free_plan?
    refute account.free_plan_events_capped?
  end

  test "trial plan accepts events via API" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    sign_in user
    ActsAsTenant.current_tenant = account

    account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now,
      cached_events_used: 100
    )

    project = account.projects.first
    unless project
      post projects_path, params: {
        project: {
          name: "Trial API Test #{SecureRandom.hex(4)}",
          environment: "production",
          url: "https://trial-api-#{SecureRandom.hex(4)}.example.com"
        }
      }
      project = account.projects.reload.last
    end

    token = project.api_tokens.active.first
    api_headers = { "CONTENT_TYPE" => "application/json", "X-Project-Token" => token.token }

    post "/api/v1/events/errors", params: {
      exception_class: "TrialE2EError",
      message: "Error during trial period",
      backtrace: ["app/models/widget.rb:10:in `process'"],
      occurred_at: Time.current.iso8601
    }.to_json, headers: api_headers

    assert_response :created, "Trial plan should accept events"
  end

  test "trial plan allows AI summary generation" do
    account = accounts(:trial_account)
    account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now,
      cached_ai_summaries_used: 5
    )

    assert account.within_quota?(:ai_summaries),
      "Trial plan should have AI summaries available (5/20 used)"
    assert account.eligible_for_auto_ai_summary?,
      "Trial plan should be eligible for auto AI summary"
  end

  # ===========================================================================
  # 3. Incomplete Stripe subscription does NOT upgrade plan
  # ===========================================================================

  test "incomplete subscription does NOT upgrade trial to team E2E" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    sign_in user
    ActsAsTenant.current_tenant = account

    account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now,
      event_quota: 50_000,
      cached_events_used: 1_000
    )

    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_e2e_incomplete_#{SecureRandom.hex(4)}" }

    team_price_id = "price_e2e_incomplete_#{SecureRandom.hex(4)}"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => pay_customer.processor_id,
          "id" => "sub_e2e_incomplete_#{SecureRandom.hex(4)}",
          "status" => "incomplete",
          "trial_end" => nil,
          "current_period_start" => nil,
          "current_period_end" => nil,
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

    assert_equal "trial", account.current_plan,
      "Plan should remain trial — incomplete subscription must not upgrade"
    assert_equal 50_000, account.event_quota,
      "Quota should remain unchanged"
    assert account.on_trial?,
      "Account should still be on trial"

    # Usage counters should NOT have been reset (no upgrade happened)
    assert_equal 1_000, account.cached_events_used,
      "Usage counters should NOT be reset for incomplete subscription"

    # Pay::Subscription record should still exist for tracking
    pay_sub = Pay::Subscription.find_by(customer_id: pay_customer.id)
    assert pay_sub.present?, "Pay::Subscription should still be tracked"
    assert_equal "incomplete", pay_sub.status
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ===========================================================================
  # 4. Past-due Stripe subscription does NOT upgrade plan
  # ===========================================================================

  test "past_due subscription does NOT upgrade trial to team E2E" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    ActsAsTenant.current_tenant = account

    account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now,
      event_quota: 50_000
    )

    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_e2e_pastdue_#{SecureRandom.hex(4)}" }

    team_price_id = "price_e2e_pastdue_#{SecureRandom.hex(4)}"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.updated",
      "data" => {
        "object" => {
          "customer" => pay_customer.processor_id,
          "id" => "sub_e2e_pastdue_#{SecureRandom.hex(4)}",
          "status" => "past_due",
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

    assert_equal "trial", account.current_plan,
      "Plan should remain trial — past_due subscription must not upgrade"
    assert account.on_trial?
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ===========================================================================
  # 5. Active Stripe subscription upgrades trial → team
  # ===========================================================================

  test "active subscription upgrades trial to team with usage reset E2E" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    user.update!(confirmed_at: Time.current) unless user.confirmed_at.present?
    sign_in user
    ActsAsTenant.current_tenant = account

    account.update!(
      current_plan: "trial",
      trial_ends_at: 5.days.from_now,
      event_quota: 50_000,
      cached_events_used: 8_000,
      cached_ai_summaries_used: 12,
      cached_pull_requests_used: 4
    )

    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_e2e_active_#{SecureRandom.hex(4)}" }

    team_price_id = "price_e2e_active_#{SecureRandom.hex(4)}"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    ActionMailer::Base.deliveries.clear

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => pay_customer.processor_id,
          "id" => "sub_e2e_active_#{SecureRandom.hex(4)}",
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

    assert_equal "team", account.current_plan,
      "Plan should be upgraded to team"
    assert_equal 50_000, account.event_quota,
      "Quota should be set to team level"

    # Usage counters reset on upgrade
    assert_equal 0, account.cached_events_used,
      "Events should be reset on trial→team upgrade"
    assert_equal 0, account.cached_ai_summaries_used,
      "AI summaries should be reset"
    assert_equal 0, account.cached_pull_requests_used,
      "PRs should be reset"

    # Pay::Subscription created with active status
    pay_sub = Pay::Subscription.find_by(customer_id: pay_customer.id)
    assert pay_sub.present?
    assert_equal "active", pay_sub.status

    # Welcome email enqueued
    perform_enqueued_jobs
    welcome_email = ActionMailer::Base.deliveries.find { |e|
      e.subject.include?("Welcome to ActiveRabbit Team") || e.subject.include?("Team")
    }
    assert welcome_email.present?, "Welcome email should be sent on trial→team upgrade"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ===========================================================================
  # 6. Trial expiration without payment → downgrade to free
  # ===========================================================================

  test "trial expiration job downgrades expired trial to free E2E" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    ActsAsTenant.current_tenant = account

    account.update!(
      current_plan: "trial",
      trial_ends_at: 3.days.ago,
      event_quota: 50_000,
      cached_events_used: 15_000,
      cached_ai_summaries_used: 10
    )

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

    assert_equal "free", account.current_plan,
      "Account should be downgraded to free"
    assert_equal 5_000, account.event_quota,
      "Quota should be set to free plan level"
    assert_equal 0, account.cached_events_used,
      "Events should be reset on downgrade"
    assert_equal 0, account.cached_ai_summaries_used,
      "AI summaries should be reset on downgrade"

    # Free plan restrictions now apply
    assert account.on_free_plan?
    assert_equal 0, account.ai_summaries_quota
    assert_equal 5, account.data_retention_days
    refute account.slack_notifications_allowed?
    refute account.eligible_for_auto_ai_summary?

    # Downgrade email sent
    downgrade_email = ActionMailer::Base.deliveries.find { |e|
      e.subject.downcase.include?("free")
    }
    assert downgrade_email.present?, "Should send downgrade notification email"
  end

  test "expired trial effective_plan_key returns :free without explicit downgrade" do
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 1.day.ago)

    refute account.on_trial?
    assert account.trial_expired?

    account.stub(:has_payment_method?, false) do
      account.stub(:active_subscription?, false) do
        assert_equal :free, account.send(:effective_plan_key),
          "Dynamic fallback should return :free for expired trial"
        assert_equal "Free", account.effective_plan_name
        assert_equal 5_000, account.event_quota_value
        assert_equal 0, account.ai_summaries_quota
        assert account.on_free_plan?
      end
    end
  end

  # ===========================================================================
  # 7. Trial reminders sent at correct intervals
  # ===========================================================================

  test "trial reminder check sends 4-day pre-expiry email" do
    account = accounts(:trial_account)
    account.update!(trial_ends_at: 4.days.from_now, current_plan: "trial")

    mail_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_now, true)

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      if args[:account] == account && args[:days_left] == 4
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

    assert mail_sent, "Should send 4-day trial reminder"
  end

  test "trial reminder skips account with active subscription" do
    account = accounts(:trial_account)
    account.update!(trial_ends_at: 4.days.from_now, current_plan: "trial")

    mail_sent = false
    original_method = Account.instance_method(:active_subscription?)
    Account.define_method(:active_subscription?) { true }

    LifecycleMailer.stub(:trial_ending_soon, ->(**args) {
      mail_sent = true if args[:account] == account
      Minitest::Mock.new
    }) do
      LifecycleMailer.stub(:trial_end_today, ->(**args) { Minitest::Mock.new }) do
        LifecycleMailer.stub(:trial_expired_warning, ->(**args) { Minitest::Mock.new }) do
          TrialReminderCheckJob.perform_now
        end
      end
    end

    refute mail_sent, "Should NOT send reminder if account has active subscription"
  ensure
    Account.define_method(:active_subscription?, original_method)
  end

  # ===========================================================================
  # 8. Data retention treats expired trials as free-tier
  # ===========================================================================

  test "data retention job includes expired trial accounts in free-tier cleanup" do
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 2.days.ago)

    ActsAsTenant.without_tenant do
      free_ids = Account.where(current_plan: %w[free developer trial]).where(
        "trial_ends_at IS NULL OR trial_ends_at < ?", Time.current
      ).pluck(:id)

      assert_includes free_ids, account.id,
        "Expired trial should be included in free-tier data retention"
    end
  end

  test "data retention job excludes active trial accounts from free-tier cleanup" do
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 7.days.from_now)

    ActsAsTenant.without_tenant do
      free_ids = Account.where(current_plan: %w[free developer trial]).where(
        "trial_ends_at IS NULL OR trial_ends_at < ?", Time.current
      ).pluck(:id)

      refute_includes free_ids, account.id,
        "Active trial should NOT be treated as free-tier for data retention"
    end
  end

  # ===========================================================================
  # 9. Full journey: signup → trial → incomplete checkout → retry → team
  # ===========================================================================

  test "full journey: incomplete checkout does not break trial then active upgrade works" do
    email = "e2e_incomplete_#{SecureRandom.hex(4)}@example.com"

    # --- Step 1: Signup → trial ---
    post user_registration_path, params: {
      user: {
        email: email,
        password: "journey_pass_123",
        password_confirmation: "journey_pass_123"
      }
    }

    user = User.find_by(email: email)
    account = user.account
    assert_equal "trial", account.current_plan, "Step 1: starts on trial"
    assert account.on_trial?, "Step 1: on trial"

    user.update!(confirmed_at: Time.current)
    sign_in user
    ActsAsTenant.current_tenant = account

    # --- Step 2: Create project and send events ---
    post projects_path, params: {
      project: {
        name: "Journey App #{SecureRandom.hex(4)}",
        environment: "production",
        url: "https://journey-#{SecureRandom.hex(4)}.example.com"
      }
    }
    assert_response :redirect

    # --- Step 3: Attempt checkout → Stripe subscription incomplete ---
    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_journey_#{SecureRandom.hex(4)}" }

    team_price_id = "price_journey_team_#{SecureRandom.hex(4)}"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    incomplete_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => pay_customer.processor_id,
          "id" => "sub_journey_inc_#{SecureRandom.hex(4)}",
          "status" => "incomplete",
          "trial_end" => nil,
          "current_period_start" => nil,
          "current_period_end" => nil,
          "items" => {
            "data" => [
              { "price" => { "id" => team_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: incomplete_event).call
    account.reload

    assert_equal "trial", account.current_plan,
      "Step 3: still on trial after incomplete checkout"
    assert account.on_trial?

    # --- Step 4: User retries → subscription becomes active ---
    active_event = {
      "type" => "customer.subscription.updated",
      "data" => {
        "object" => {
          "customer" => pay_customer.processor_id,
          "id" => "sub_journey_active_#{SecureRandom.hex(4)}",
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

    StripeEventHandler.new(event: active_event).call
    account.reload

    assert_equal "team", account.current_plan,
      "Step 4: upgraded to team after active subscription"
    refute account.on_free_plan?
    assert_equal 50_000, account.event_quota
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ===========================================================================
  # 10. Full journey: signup → trial → expire → free → upgrade → team
  # ===========================================================================

  test "full journey: trial expires then user upgrades from free to team" do
    email = "e2e_expire_#{SecureRandom.hex(4)}@example.com"

    # --- Step 1: Signup → trial ---
    post user_registration_path, params: {
      user: {
        email: email,
        password: "expire_pass_123",
        password_confirmation: "expire_pass_123"
      }
    }

    user = User.find_by(email: email)
    account = user.account
    assert_equal "trial", account.current_plan
    assert account.on_trial?

    user.update!(confirmed_at: Time.current)
    sign_in user
    ActsAsTenant.current_tenant = account

    # --- Step 2: Time passes, trial expires ---
    account.update!(trial_ends_at: 2.days.ago, cached_events_used: 5_000)
    refute account.on_trial?
    assert account.trial_expired?

    # --- Step 3: TrialExpirationJob runs → downgrade to free ---
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
    assert_equal "free", account.current_plan, "Step 3: downgraded to free"
    assert_equal 5_000, account.event_quota
    assert_equal 0, account.cached_events_used, "Usage reset on downgrade"

    # --- Step 4: Free plan restrictions apply ---
    assert account.on_free_plan?
    assert_equal 0, account.ai_summaries_quota
    refute account.slack_notifications_allowed?
    refute account.eligible_for_auto_ai_summary?

    # --- Step 5: User upgrades via Stripe checkout → team ---
    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_e2e_expire_#{SecureRandom.hex(4)}" }

    team_price_id = "price_e2e_expire_team_#{SecureRandom.hex(4)}"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    ActionMailer::Base.deliveries.clear

    active_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => pay_customer.processor_id,
          "id" => "sub_e2e_expire_upgrade_#{SecureRandom.hex(4)}",
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

    StripeEventHandler.new(event: active_event).call
    account.reload

    assert_equal "team", account.current_plan, "Step 5: upgraded to team"
    assert_equal 50_000, account.event_quota
    assert_equal 0, account.cached_events_used, "Usage reset on upgrade"
    refute account.on_free_plan?
    assert_equal 20, account.ai_summaries_quota
    assert_equal 31, account.data_retention_days
    assert account.slack_notifications_allowed?

    # Welcome email sent
    perform_enqueued_jobs
    welcome_email = ActionMailer::Base.deliveries.find { |e|
      e.subject.include?("Team") || e.subject.include?("Welcome")
    }
    assert welcome_email.present?, "Step 5: welcome email sent on free→team upgrade"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ===========================================================================
  # 11. Trial plan needing_payment_reminder scope
  # ===========================================================================

  test "needing_payment_reminder includes expired trial without subscription" do
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 1.day.ago)

    ActsAsTenant.without_tenant do
      result = Account.needing_payment_reminder
      assert_includes result, account,
        "Expired trial without subscription should need payment reminder"
    end
  end

  test "needing_payment_reminder excludes active trial" do
    account = accounts(:trial_account)
    account.update!(current_plan: "trial", trial_ends_at: 7.days.from_now)

    ActsAsTenant.without_tenant do
      result = Account.needing_payment_reminder
      refute_includes result, account,
        "Active trial should NOT need payment reminder"
    end
  end

  test "needing_payment_reminder excludes trial with active subscription" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    account.update!(current_plan: "trial", trial_ends_at: 1.day.ago)

    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_e2e_scope_#{SecureRandom.hex(4)}" }

    Pay::Subscription.create!(
      customer: pay_customer,
      processor_id: "sub_e2e_scope_#{SecureRandom.hex(4)}",
      name: "default",
      processor_plan: "price_test",
      status: "active",
      quantity: 1
    )

    ActsAsTenant.without_tenant do
      result = Account.needing_payment_reminder
      refute_includes result, account,
        "Expired trial with active subscription should NOT need payment reminder"
    end
  end

  # ===========================================================================
  # 12. Event hard cap only applies to free, not trial
  # ===========================================================================

  test "trial plan has no hard cap on events" do
    account = accounts(:trial_account)
    account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now,
      cached_events_used: 999_999
    )

    refute account.free_plan_events_capped?,
      "Trial plan should never be hard-capped even when over quota"
  end

  test "free plan has hard cap on events" do
    account = accounts(:free_account)
    account.update!(cached_events_used: 5_001)

    assert account.free_plan_events_capped?,
      "Free plan should be hard-capped when over quota"
  end

  # ===========================================================================
  # 13. Business plan upgrade from trial
  # ===========================================================================

  test "active business subscription upgrades trial to business" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    ActsAsTenant.current_tenant = account

    account.update!(
      current_plan: "trial",
      trial_ends_at: 5.days.from_now,
      event_quota: 50_000
    )

    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_e2e_biz_#{SecureRandom.hex(4)}" }

    biz_price_id = "price_e2e_biz_#{SecureRandom.hex(4)}"
    original_env = ENV["STRIPE_PRICE_BUSINESS_MONTHLY"]
    ENV["STRIPE_PRICE_BUSINESS_MONTHLY"] = biz_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => pay_customer.processor_id,
          "id" => "sub_e2e_biz_#{SecureRandom.hex(4)}",
          "status" => "active",
          "trial_end" => nil,
          "current_period_start" => Time.current.to_i,
          "current_period_end" => 1.month.from_now.to_i,
          "items" => {
            "data" => [
              { "price" => { "id" => biz_price_id }, "quantity" => 1 }
            ]
          }
        }
      }
    }

    StripeEventHandler.new(event: subscription_event).call
    account.reload

    assert_equal "business", account.current_plan,
      "Should upgrade from trial to business"
    assert_equal 100, account.ai_summaries_quota,
      "Business plan should have 100 AI summaries"
    assert_equal 31, account.data_retention_days
  ensure
    ENV["STRIPE_PRICE_BUSINESS_MONTHLY"] = original_env
  end

  # ===========================================================================
  # 14. Trialing Stripe subscription (Stripe-managed trial) upgrades plan
  # ===========================================================================

  test "Stripe trialing subscription upgrades trial plan" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    ActsAsTenant.current_tenant = account

    account.update!(
      current_plan: "trial",
      trial_ends_at: 5.days.from_now,
      event_quota: 50_000
    )

    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_e2e_strialing_#{SecureRandom.hex(4)}" }

    team_price_id = "price_e2e_strialing_#{SecureRandom.hex(4)}"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => pay_customer.processor_id,
          "id" => "sub_e2e_strialing_#{SecureRandom.hex(4)}",
          "status" => "trialing",
          "trial_end" => 14.days.from_now.to_i,
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

    assert_equal "team", account.current_plan,
      "Stripe trialing status should upgrade plan (billable)"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ===========================================================================
  # 15. Subscription deleted does NOT restore trial
  # ===========================================================================

  test "subscription deletion disables AI but does not change plan back to trial" do
    account = accounts(:trial_account)
    user = users(:trial_user)
    ActsAsTenant.current_tenant = account

    account.update!(
      current_plan: "team",
      trial_ends_at: nil,
      ai_mode_enabled: true
    )

    pay_customer = Pay::Customer.find_or_create_by!(
      owner: user, processor: "stripe"
    ) { |c| c.processor_id = "cus_e2e_del_#{SecureRandom.hex(4)}" }

    sub_id = "sub_e2e_del_#{SecureRandom.hex(4)}"
    Pay::Subscription.create!(
      customer: pay_customer,
      processor_id: sub_id,
      name: "default",
      processor_plan: "price_test",
      status: "active",
      quantity: 1
    )

    delete_event = {
      "type" => "customer.subscription.deleted",
      "data" => {
        "object" => {
          "customer" => pay_customer.processor_id,
          "id" => sub_id
        }
      }
    }

    StripeEventHandler.new(event: delete_event).call
    account.reload

    refute account.ai_mode_enabled?,
      "AI mode should be disabled on subscription deletion"
    assert_equal "team", account.current_plan,
      "Plan should remain team (TrialExpirationJob handles downgrade)"

    pay_sub = Pay::Subscription.find_by(processor_id: sub_id)
    assert_equal "canceled", pay_sub.status
  end
end
