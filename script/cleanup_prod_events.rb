#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# Production Event Cleanup Script
# =============================================================================
#
# Run this script locally to clean up old events from the production database.
#
# USAGE:
#   1. Set DATABASE_URL to your production database:
#      export DATABASE_URL="postgres://user:pass@host:5432/activerabbit_production"
#
#   2. Run dry-run first to see what would be deleted:
#      bundle exec ruby script/cleanup_prod_events.rb --dry-run
#
#   3. Run actual cleanup:
#      bundle exec ruby script/cleanup_prod_events.rb
#
# OPTIONS:
#   --dry-run         Show what would be deleted without deleting
#   --retention=DAYS  Keep events newer than DAYS (default: 30)
#   --batch=SIZE      Delete in batches of SIZE (default: 50000)
#   --stats           Just show statistics, don't delete anything
#
# =============================================================================

require_relative "../config/environment"

# Parse arguments
dry_run = ARGV.include?("--dry-run")
stats_only = ARGV.include?("--stats")
retention_days = ARGV.find { |a| a.start_with?("--retention=") }&.split("=")&.last&.to_i || 30
batch_size = ARGV.find { |a| a.start_with?("--batch=") }&.split("=")&.last&.to_i || 50_000

def format_number(n)
  n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
end

def print_header(title)
  puts
  puts "=" * 60
  puts title
  puts "=" * 60
end

# Connection info
db_config = ActiveRecord::Base.connection_db_config.configuration_hash
db_host = db_config[:host] || "localhost"
db_name = db_config[:database] || "unknown"

print_header "Production Event Cleanup"
puts "Database: #{db_name}@#{db_host}"
puts "Retention: #{retention_days} days (cutoff: #{retention_days.days.ago.to_date})"
puts "Batch size: #{format_number(batch_size)}"
puts

# Safety check - recognize common production hosts
production_hosts = %w[render aws heroku ubicloud neon supabase]
is_production = production_hosts.any? { |h| db_host.include?(h) } || ENV["FORCE_RUN"]

unless is_production
  puts "⚠️  WARNING: This doesn't look like a production database."
  puts "   Host: #{db_host}"
  puts
  puts "   Set FORCE_RUN=1 to run anyway, or check your DATABASE_URL."
  exit 1
end

cutoff = retention_days.days.ago

# Bypass acts_as_tenant scoping for all maintenance queries
ActsAsTenant.without_tenant do
  # Stats mode
  if stats_only || dry_run
    print_header "Event Statistics"

    puts "Events (errors):"
    [7, 14, 30, 60, 90].each do |days|
      count = Event.where("occurred_at >= ?", days.days.ago).count
      puts "  Last #{days.to_s.rjust(2)} days: #{format_number(count).rjust(12)}"
    end
    total_events = Event.count
    old_events = Event.where("occurred_at < ?", cutoff).count
    puts "  Total:          #{format_number(total_events).rjust(12)}"
    puts "  To delete:      #{format_number(old_events).rjust(12)}"
    puts

    puts "Performance Events:"
    [7, 14, 30, 60, 90].each do |days|
      count = PerformanceEvent.where("occurred_at >= ?", days.days.ago).count
      puts "  Last #{days.to_s.rjust(2)} days: #{format_number(count).rjust(12)}"
    end
    total_perf = PerformanceEvent.count
    old_perf = PerformanceEvent.where("occurred_at < ?", cutoff).count
    puts "  Total:          #{format_number(total_perf).rjust(12)}"
    puts "  To delete:      #{format_number(old_perf).rjust(12)}"

    if dry_run
      print_header "DRY RUN - No changes made"
      puts "Would delete:"
      puts "  #{format_number(old_events)} events"
      puts "  #{format_number(old_perf)} performance_events"
      puts
      puts "Run without --dry-run to actually delete."
    end

    exit 0
  end

  # Actual deletion
  print_header "Starting Cleanup"

  puts "⚠️  This will DELETE data from production!"
  puts
  print "Type 'yes' to continue: "
  confirmation = $stdin.gets.chomp

  unless confirmation.downcase == "yes"
    puts "Aborted."
    exit 1
  end

  puts
  puts "Deleting events older than #{cutoff.to_date}..."

  total_events_deleted = 0
  loop do
    deleted = Event.where("occurred_at < ?", cutoff)
                   .limit(batch_size)
                   .delete_all

    break if deleted == 0

    total_events_deleted += deleted
    puts "  Batch: #{format_number(deleted)} | Total: #{format_number(total_events_deleted)}"

    sleep 0.1 # Reduce DB pressure
  end

  puts "Events deleted: #{format_number(total_events_deleted)}"
  puts

  puts "Deleting performance_events older than #{cutoff.to_date}..."

  total_perf_deleted = 0
  loop do
    deleted = PerformanceEvent.where("occurred_at < ?", cutoff)
                              .limit(batch_size)
                              .delete_all

    break if deleted == 0

    total_perf_deleted += deleted
    puts "  Batch: #{format_number(deleted)} | Total: #{format_number(total_perf_deleted)}"

    sleep 0.1
  end

  puts "Performance events deleted: #{format_number(total_perf_deleted)}"

  print_header "Cleanup Complete"
  puts "Total records deleted: #{format_number(total_events_deleted + total_perf_deleted)}"
  puts
  puts "Consider running VACUUM ANALYZE on production:"
  puts "  VACUUM ANALYZE events;"
  puts "  VACUUM ANALYZE performance_events;"
end
