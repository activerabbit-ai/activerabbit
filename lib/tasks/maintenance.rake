# frozen_string_literal: true

namespace :maintenance do
  desc "Batch delete old events and performance_events (safe for production)"
  task :cleanup_old_events, [:retention_days, :batch_size, :dry_run] => :environment do |_t, args|
    retention_days = (args[:retention_days] || ENV.fetch("RETENTION_DAYS", 30)).to_i
    batch_size = (args[:batch_size] || ENV.fetch("BATCH_SIZE", 50_000)).to_i
    dry_run = args[:dry_run].to_s == "true" || ENV["DRY_RUN"] == "true"

    puts "=" * 60
    puts "Event Cleanup Task"
    puts "=" * 60
    puts "Database: #{ActiveRecord::Base.connection_db_config.configuration_hash[:host] || 'localhost'}"
    puts "Retention: #{retention_days} days"
    puts "Batch size: #{batch_size.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "Mode: #{dry_run ? 'DRY RUN (no deletions)' : 'LIVE'}"
    puts "Cutoff date: #{retention_days.days.ago.to_date}"
    puts "=" * 60
    puts

    # Bypass acts_as_tenant scoping for maintenance queries
    ActsAsTenant.without_tenant do
      if dry_run
        # Just count what would be deleted
        events_count = Event.where("occurred_at < ?", retention_days.days.ago).count
        perf_events_count = PerformanceEvent.where("occurred_at < ?", retention_days.days.ago).count

        puts "[DRY RUN] Would delete #{events_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} events"
        puts "[DRY RUN] Would delete #{perf_events_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} performance_events"
        puts
        puts "Run without dry_run to actually delete:"
        puts "  rake maintenance:cleanup_old_events[#{retention_days},#{batch_size},false]"
      else
        total_events_deleted = 0
        total_perf_events_deleted = 0

        # Delete events in batches
        puts "Deleting old events..."
        loop do
          deleted = Event.where("occurred_at < ?", retention_days.days.ago)
                         .limit(batch_size)
                         .delete_all

          break if deleted == 0

          total_events_deleted += deleted
          puts "  Deleted #{deleted} events (total: #{total_events_deleted.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse})"

          # Small pause to reduce DB load
          sleep 0.1
        end

        puts "Completed: #{total_events_deleted.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} events deleted"
        puts

        # Delete performance_events in batches
        puts "Deleting old performance_events..."
        loop do
          deleted = PerformanceEvent.where("occurred_at < ?", retention_days.days.ago)
                                    .limit(batch_size)
                                    .delete_all

          break if deleted == 0

          total_perf_events_deleted += deleted
          puts "  Deleted #{deleted} performance_events (total: #{total_perf_events_deleted.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse})"

          sleep 0.1
        end

        puts "Completed: #{total_perf_events_deleted.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} performance_events deleted"
        puts
        puts "=" * 60
        puts "Total deleted: #{(total_events_deleted + total_perf_events_deleted).to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} records"
        puts "=" * 60
      end
    end
  end

  desc "Show event counts by age"
  task event_stats: :environment do
    puts "=" * 60
    puts "Event Statistics"
    puts "=" * 60
    puts "Database: #{ActiveRecord::Base.connection_db_config.configuration_hash[:host] || 'localhost'}"
    puts "=" * 60
    puts

    # Bypass acts_as_tenant scoping for maintenance queries
    ActsAsTenant.without_tenant do
      # Events breakdown
      puts "Events (errors):"
      [7, 14, 30, 60, 90].each do |days|
        count = Event.where("occurred_at >= ?", days.days.ago).count
        puts "  Last #{days.to_s.rjust(2)} days: #{count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse.rjust(12)}"
      end
      total_events = Event.count
      old_events = Event.where("occurred_at < ?", 30.days.ago).count
      puts "  Total:       #{total_events.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse.rjust(12)}"
      puts "  Older than 30d: #{old_events.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse.rjust(9)}"
      puts

      # Performance events breakdown
      puts "Performance Events:"
      [7, 14, 30, 60, 90].each do |days|
        count = PerformanceEvent.where("occurred_at >= ?", days.days.ago).count
        puts "  Last #{days.to_s.rjust(2)} days: #{count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse.rjust(12)}"
      end
      total_perf = PerformanceEvent.count
      old_perf = PerformanceEvent.where("occurred_at < ?", 30.days.ago).count
      puts "  Total:       #{total_perf.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse.rjust(12)}"
      puts "  Older than 30d: #{old_perf.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse.rjust(9)}"
      puts

      # Disk space estimate (rough)
      puts "Estimated cleanup impact (30 day retention):"
      puts "  Events to delete: #{old_events.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      puts "  Perf events to delete: #{old_perf.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    end
  end

  desc "Vacuum analyze after cleanup (run on prod carefully)"
  task vacuum_events: :environment do
    puts "Running VACUUM ANALYZE on events tables..."
    puts "This may take a while on large tables."
    puts

    ActiveRecord::Base.connection.execute("VACUUM ANALYZE events")
    puts "  events: done"

    ActiveRecord::Base.connection.execute("VACUUM ANALYZE performance_events")
    puts "  performance_events: done"

    puts
    puts "Vacuum complete!"
  end
end
