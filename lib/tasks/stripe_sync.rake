# frozen_string_literal: true

namespace :stripe do
  desc "Sync a Stripe subscription to an account (by project slug). Use when payment succeeded but app still shows free/trial. " \
       "Env: PROJECT_SLUG, STRIPE_SUBSCRIPTION_ID; optional: CUSTOMER_EMAIL. " \
       "Ensure STRIPE_PRICE_TEAM_MONTHLY (and STRIPE_SECRET_KEY) are set in production."
  task :sync_subscription_to_account, [:project_slug, :subscription_id] => :environment do |_t, args|
    project_slug = args[:project_slug].presence || ENV["PROJECT_SLUG"]
    subscription_id = args[:subscription_id].presence || ENV["STRIPE_SUBSCRIPTION_ID"]
    customer_email = ENV["CUSTOMER_EMAIL"].presence

    unless project_slug.present?
      puts "Usage: rake stripe:sync_subscription_to_account[grittyapp-production_api,sub_1T2bMSQ7xtE658H3SdPr1Aj9]"
      puts "   or: PROJECT_SLUG=grittyapp-production_api STRIPE_SUBSCRIPTION_ID=sub_xxx rake stripe:sync_subscription_to_account"
      exit 1
    end
    unless subscription_id.present?
      puts "STRIPE_SUBSCRIPTION_ID (or second arg) required."
      exit 1
    end

    ActsAsTenant.without_tenant do
      project = Project.find_by(slug: project_slug)
      unless project
        puts "Project not found with slug: #{project_slug}"
        exit 1
      end

      account = project.account
      puts "Account: #{account.name} (id=#{account.id}), current_plan=#{account.current_plan}"

      unless ENV["STRIPE_SECRET_KEY"].present?
        puts "STRIPE_SECRET_KEY not set. Set it so we can fetch the subscription from Stripe."
        exit 1
      end

      Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
      sub = Stripe::Subscription.retrieve(subscription_id, expand: ["items.data.price"])
      customer_id = sub.customer

      pay_customer = Pay::Customer.find_by(processor: "stripe", processor_id: customer_id)
      if pay_customer
        owner = pay_customer.owner
        owner_account = owner.is_a?(User) ? owner.account : owner
        unless owner_account&.id == account.id
          puts "Stripe customer #{customer_id} is already linked to another account (owner: #{owner.class} ##{owner.try(:id)}). " \
               "Expected account #{account.id} (#{account.name})."
          exit 1
        end
        puts "Pay::Customer already linked to user in this account."
      else
        user = if customer_email.present?
                 account.users.find_by(email: customer_email)
               else
                 account.users.order(:id).first
               end
        unless user
          puts "No user in account to attach Stripe customer to. Add CUSTOMER_EMAIL=devops@grittyfactor.com or ensure account has users."
          exit 1
        end
        Pay::Customer.create!(
          owner: user,
          processor: "stripe",
          processor_id: customer_id
        )
        puts "Created Pay::Customer for user #{user.email} (id=#{user.id}) linked to Stripe customer #{customer_id}."
      end

      team_price = ENV["STRIPE_PRICE_TEAM_MONTHLY"].presence || ENV["STRIPE_PRICE_TEAM_ANNUAL"].presence
      if team_price.blank?
        puts "WARNING: STRIPE_PRICE_TEAM_MONTHLY (or STRIPE_PRICE_TEAM_ANNUAL) not set. Plan may not be detected as 'team'."
      else
        sub_price_id = sub.items.data.first&.price&.id
        puts "Stripe subscription price: #{sub_price_id}; app Team price env: #{team_price}" + (sub_price_id == team_price ? " (match)" : " (no match – set env to #{sub_price_id} for Team)")
      end

      event = { "type" => "customer.subscription.updated", "data" => { "object" => sub } }
      StripeEventHandler.new(event: event).call

      account.reload
      # Re-enable Slack so notifications continue after subscribe (app may have treated account as free before sync)
      if account.current_plan.in?(%w[team business]) && account.slack_configured?
        account.enable_slack_notifications!
        puts "Slack notifications re-enabled for account (slack_configured? was true)."
      end
      puts "Done. Account current_plan=#{account.current_plan}, active_subscription?=#{account.active_subscription?}"
    end
  end

  desc "Ensure Slack notifications are enabled for a paid account (by account name). " \
       "Use when Slack stopped after subscribing. Optionally set plan to team if account is already paid. " \
       "Usage: rake stripe:ensure_slack_for_account[\"Rescuehub Account\"]"
  task :ensure_slack_for_account, [:account_name] => :environment do |_t, args|
    account_name = args[:account_name].presence || ENV["ACCOUNT_NAME"]
    unless account_name.present?
      puts "Usage: rake stripe:ensure_slack_for_account[\"Rescuehub Account\"]"
      puts "   or: ACCOUNT_NAME='Rescuehub Account' rake stripe:ensure_slack_for_account"
      exit 1
    end

    ActsAsTenant.without_tenant do
      account = Account.find_by(name: account_name)
      unless account
        puts "Account not found: #{account_name}"
        exit 1
      end

      puts "Account: #{account.name} (id=#{account.id}), current_plan=#{account.current_plan}, slack_configured?=#{account.slack_configured?}"

      if account.current_plan.blank? || account.current_plan.to_s.downcase == "free"
        puts "Setting current_plan to 'team' so Slack is allowed (paid account)."
        account.update!(
          current_plan: "team",
          billing_interval: "month",
          event_quota: 50_000
        )
      end

      unless account.slack_configured?
        puts "Slack not configured (no webhook URL). Configure Slack in account settings first."
        exit 1
      end

      account.enable_slack_notifications!
      puts "Slack notifications enabled. slack_notifications_enabled?=#{account.slack_notifications_enabled?}"
    end
  end
end
