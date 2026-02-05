# frozen_string_literal: true

namespace :users do
  desc "Send confirmation emails to all unconfirmed users"
  task send_confirmation_emails: :environment do
    unconfirmed_users = User.where(confirmed_at: nil)
    total = unconfirmed_users.count

    puts "Found #{total} unconfirmed users"

    if total == 0
      puts "No unconfirmed users found. Nothing to do."
      exit
    end

    print "Send confirmation emails to all #{total} users? (yes/no): "
    answer = $stdin.gets&.chomp

    unless answer&.downcase == "yes"
      puts "Aborted."
      exit
    end

    sent = 0
    failed = 0

    unconfirmed_users.find_each.with_index do |user, index|
      # Rate limit: 2 emails per second (Resend limit)
      sleep(0.6) if index > 0

      begin
        user.send_confirmation_instructions
        sent += 1
        puts "[#{sent}/#{total}] Sent to: #{user.email}"
      rescue => e
        failed += 1
        puts "[ERROR] Failed for #{user.email}: #{e.message}"
      end
    end

    puts "\nDone! Sent: #{sent}, Failed: #{failed}"
  end

  desc "Confirm all existing users without sending emails"
  task confirm_all: :environment do
    unconfirmed_users = User.where(confirmed_at: nil)
    total = unconfirmed_users.count

    puts "Found #{total} unconfirmed users"

    if total == 0
      puts "No unconfirmed users found. Nothing to do."
      exit
    end

    print "Confirm all #{total} users without sending emails? (yes/no): "
    answer = $stdin.gets&.chomp

    unless answer&.downcase == "yes"
      puts "Aborted."
      exit
    end

    updated = User.where(confirmed_at: nil).update_all(confirmed_at: Time.current)
    puts "Done! Confirmed #{updated} users."
  end
end
