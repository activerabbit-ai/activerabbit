# frozen_string_literal: true

namespace :trials do
  desc "Reset trial for ALL accounts: sets trial_ends_at to 14 days from now, plan to 'team', quota to 50k"
  task reset_all: :environment do
    trial_days = Rails.configuration.x.trial_days
    new_trial_end = trial_days.days.from_now

    puts "=" * 60
    puts "Trial Reset — ALL Accounts"
    puts "=" * 60
    puts "Trial duration: #{trial_days} days"
    puts "New trial_ends_at: #{new_trial_end}"
    puts "Plan: team | Quota: 50,000"
    puts "=" * 60
    puts

    count = 0
    Account.find_each do |account|
      old_plan = account.current_plan
      old_trial = account.trial_ends_at
      account.update!(
        trial_ends_at: new_trial_end,
        current_plan: "team",
        event_quota: 50_000
      )
      count += 1
      puts "  [#{account.id}] #{account.name}: #{old_plan} → team | trial #{old_trial&.to_date || 'nil'} → #{new_trial_end.to_date}"
    end

    puts
    puts "Done! Reset #{count} account(s)."
  end

  desc "Reset trial for a SINGLE account by ID"
  task :reset, [:account_id] => :environment do |_t, args|
    account_id = args[:account_id]
    abort "Usage: rake trials:reset[ACCOUNT_ID]" unless account_id.present?

    trial_days = Rails.configuration.x.trial_days
    new_trial_end = trial_days.days.from_now

    account = Account.find(account_id)

    puts "=" * 60
    puts "Trial Reset — Account ##{account.id} (#{account.name})"
    puts "=" * 60

    old_plan = account.current_plan
    old_trial = account.trial_ends_at

    puts "Before: plan=#{old_plan}, trial_ends_at=#{old_trial}, quota=#{account.event_quota}"

    account.update!(
      trial_ends_at: new_trial_end,
      current_plan: "team",
      event_quota: 50_000
    )

    puts "After:  plan=team, trial_ends_at=#{new_trial_end}, quota=50,000"
    puts
    puts "Done! Trial reset for #{account.name}."
  end
end
