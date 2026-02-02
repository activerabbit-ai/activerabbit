# frozen_string_literal: true

namespace :issues do
  desc "Recompute fingerprints and merge issues with new origin-based grouping strategy"
  task :recompute_fingerprints, [:dry_run] => :environment do |_t, args|
    dry_run = args[:dry_run].to_s == "true" || ENV["DRY_RUN"] == "true"

    puts "=" * 60
    puts "Issue Fingerprint Recomputation"
    puts "=" * 60
    puts "Mode: #{dry_run ? 'DRY RUN (no changes)' : 'LIVE'}"
    puts "=" * 60
    puts

    stats = Issues::FingerprintRecomputer.new(dry_run: dry_run).call

    puts
    puts "=" * 60
    puts "Summary"
    puts "=" * 60
    puts "  Issues processed: #{stats[:processed]}"
    puts "  Issues merged:    #{stats[:merged]}"
    puts "  Issues updated:   #{stats[:updated]}"
    puts "  Issues unchanged: #{stats[:unchanged]}"
    puts "  Errors:           #{stats[:errors]}"
    puts "=" * 60

    if dry_run && (stats[:merged] > 0 || stats[:updated] > 0)
      puts
      puts "Run without dry_run to apply changes:"
      puts "  rake issues:recompute_fingerprints[false]"
      puts "  # or"
      puts "  DRY_RUN=false rake issues:recompute_fingerprints"
    end
  end

  desc "Preview which issues would be merged (alias for dry run)"
  task preview_fingerprint_changes: :environment do
    Rake::Task["issues:recompute_fingerprints"].invoke("true")
  end
end
