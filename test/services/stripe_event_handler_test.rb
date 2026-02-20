require "test_helper"

class StripeEventHandlerTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:default)
    # Create a Pay::Customer if Pay is available
    @pay_customer = Pay::Customer.create!(owner: @account, processor: "stripe", processor_id: "cus_123")
  end

  test "sets past_due on payment_failed" do
    failed_event = {
      "type" => "invoice.payment_failed",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "in_1"
        }
      }
    }

    StripeEventHandler.new(event: failed_event).call
    assert @account.reload.settings["past_due"]
  end

  test "clears past_due on payment_succeeded" do
    # First set past_due
    @account.update!(settings: { "past_due" => true })

    succeeded_event = {
      "type" => "invoice.payment_succeeded",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "in_2"
        }
      }
    }

    StripeEventHandler.new(event: succeeded_event).call
    assert_nil @account.reload.settings["past_due"]
  end

  # ============================================================================
  # Usage reset on plan upgrade
  # ============================================================================

  test "resets usage counters when upgrading from free to team" do
    @account.update!(
      current_plan: "free",
      trial_ends_at: 1.month.ago,
      cached_events_used: 4_500,
      cached_performance_events_used: 100,
      cached_ai_summaries_used: 0,
      cached_pull_requests_used: 0
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    # Temporarily set the env var for the test
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_upgrade_1",
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
    @account.reload

    assert_equal "team", @account.current_plan
    assert_equal 0, @account.cached_events_used, "Events used should be reset on upgrade"
    assert_equal 0, @account.cached_performance_events_used, "Perf events should be reset"
    assert_equal 0, @account.cached_ai_summaries_used, "AI summaries should be reset"
    assert_equal 0, @account.cached_pull_requests_used, "PRs should be reset"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  test "resets usage counters when upgrading from trial to team" do
    @account.update!(
      current_plan: "trial",
      trial_ends_at: 1.day.from_now,
      cached_events_used: 2_000,
      cached_ai_summaries_used: 10,
      cached_pull_requests_used: 5
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_upgrade_2",
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
    @account.reload

    assert_equal "team", @account.current_plan
    assert_equal 0, @account.cached_events_used, "Events should be reset on trial->team"
    assert_equal 0, @account.cached_ai_summaries_used, "AI summaries should be reset"
    assert_equal 0, @account.cached_pull_requests_used, "PRs should be reset"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  test "does NOT reset usage counters when plan stays the same (team->team renewal)" do
    @account.update!(
      current_plan: "team",
      cached_events_used: 30_000,
      cached_ai_summaries_used: 12
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.updated",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_renewal_1",
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
    @account.reload

    assert_equal "team", @account.current_plan
    assert_equal 30_000, @account.cached_events_used, "Events should NOT be reset on same-plan renewal"
    assert_equal 12, @account.cached_ai_summaries_used, "AI summaries should NOT be reset"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ============================================================================
  # Welcome email on plan upgrade
  # ============================================================================

  test "sends welcome email when upgrading from free to team" do
    @account.update!(
      current_plan: "free",
      trial_ends_at: 1.month.ago,
      cached_events_used: 1_000
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_welcome_1",
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

    email_sent = false
    mock_mail = Minitest::Mock.new
    mock_mail.expect(:deliver_later, true)

    LifecycleMailer.stub(:plan_upgraded, ->(**args) {
      email_sent = true
      assert_equal @account, args[:account]
      assert_equal "team", args[:new_plan]
      mock_mail
    }) do
      StripeEventHandler.new(event: subscription_event).call
    end

    assert email_sent, "Should send welcome email on plan upgrade"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ============================================================================
  # Incomplete subscription should NOT upgrade plan
  # ============================================================================

  test "does NOT upgrade plan when subscription is incomplete" do
    @account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now,
      cached_events_used: 1_000
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_incomplete_1",
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
    @account.reload

    assert_equal "trial", @account.current_plan, "Plan should remain trial when subscription is incomplete"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  test "does NOT upgrade plan when subscription is past_due" do
    @account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.updated",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_past_due_1",
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
    @account.reload

    assert_equal "trial", @account.current_plan, "Plan should remain trial when subscription is past_due"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  test "DOES upgrade plan when subscription is active" do
    @account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now,
      cached_events_used: 1_000
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_active_1",
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
    @account.reload

    assert_equal "team", @account.current_plan, "Plan should be upgraded to team when subscription is active"
    assert_equal 0, @account.cached_events_used, "Usage counters should be reset on upgrade"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  test "still creates Pay::Subscription record for incomplete subscriptions" do
    @account.update!(
      current_plan: "trial",
      trial_ends_at: 7.days.from_now
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.created",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_incomplete_track",
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

    pay_sub = Pay::Subscription.find_by(processor_id: "sub_incomplete_track")
    assert pay_sub.present?, "Pay::Subscription record should be created even for incomplete subscriptions"
    assert_equal "incomplete", pay_sub.status
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end

  # ============================================================================
  # Welcome email (existing tests)
  # ============================================================================

  test "does NOT send welcome email on same-plan renewal" do
    @account.update!(
      current_plan: "team",
      cached_events_used: 10_000
    )

    team_price_id = ENV["STRIPE_PRICE_TEAM_MONTHLY"] || "price_team_monthly_test"
    original_env = ENV["STRIPE_PRICE_TEAM_MONTHLY"]
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = team_price_id

    subscription_event = {
      "type" => "customer.subscription.updated",
      "data" => {
        "object" => {
          "customer" => "cus_123",
          "id" => "sub_renewal_2",
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

    email_sent = false
    LifecycleMailer.stub(:plan_upgraded, ->(**args) {
      email_sent = true
      flunk "Should NOT send welcome email on same-plan renewal"
    }) do
      StripeEventHandler.new(event: subscription_event).call
    end

    refute email_sent, "Welcome email should NOT be sent on same-plan renewal"
  ensure
    ENV["STRIPE_PRICE_TEAM_MONTHLY"] = original_env
  end
end
