# frozen_string_literal: true

module Issues
  # Recomputes fingerprints for all issues using the current fingerprinting algorithm.
  # This is useful after changing the fingerprinting strategy to merge issues that
  # should now be grouped together.
  #
  # Usage:
  #   Issues::FingerprintRecomputer.new(dry_run: true).call  # Preview changes
  #   Issues::FingerprintRecomputer.new(dry_run: false).call # Apply changes
  #
  class FingerprintRecomputer
    attr_reader :dry_run, :stats

    def initialize(dry_run: true)
      @dry_run = dry_run
      @stats = { processed: 0, merged: 0, updated: 0, unchanged: 0, errors: 0 }
    end

    def call
      # Bypass acts_as_tenant scoping for maintenance operations
      ActsAsTenant.without_tenant do
        process_all_issues
      end

      stats
    end

    private

    def process_all_issues
      # Group issues by project to handle merging within each project
      Issue.find_each do |issue|
        process_issue(issue)
      rescue StandardError => e
        stats[:errors] += 1
        puts "  ERROR processing issue ##{issue.id}: #{e.message}"
      end
    end

    def process_issue(issue)
      stats[:processed] += 1

      new_fingerprint = Issue.send(:generate_fingerprint,
        issue.exception_class,
        issue.top_frame,
        issue.controller_action
      )

      if issue.fingerprint == new_fingerprint
        stats[:unchanged] += 1
        return
      end

      # Check if there's already an issue with the new fingerprint in the same project
      existing = Issue.where(project_id: issue.project_id, fingerprint: new_fingerprint)
                      .where.not(id: issue.id)
                      .first

      if existing
        merge_issues(issue, existing)
      else
        update_fingerprint(issue, new_fingerprint)
      end
    end

    def merge_issues(source_issue, target_issue)
      action = dry_run ? "[DRY RUN] Would merge" : "Merging"
      puts "  #{action} issue ##{source_issue.id} into ##{target_issue.id}"
      puts "    Exception: #{source_issue.exception_class}"
      puts "    Source controller: #{source_issue.controller_action}"
      puts "    Target controller: #{target_issue.controller_action}"
      puts "    Origin: #{source_issue.top_frame}"

      unless dry_run
        # Update target issue with merged stats
        target_issue.update!(
          count: target_issue.count + source_issue.count,
          first_seen_at: [target_issue.first_seen_at, source_issue.first_seen_at].compact.min,
          last_seen_at: [target_issue.last_seen_at, source_issue.last_seen_at].compact.max
        )

        # Move all events from source to target
        source_issue.events.update_all(issue_id: target_issue.id)

        # Delete the source issue
        source_issue.destroy
      end

      stats[:merged] += 1
    end

    def update_fingerprint(issue, new_fingerprint)
      action = dry_run ? "[DRY RUN] Would update" : "Updating"
      puts "  #{action} fingerprint for issue ##{issue.id}"
      puts "    Exception: #{issue.exception_class}"
      puts "    Controller: #{issue.controller_action}"
      puts "    Old fingerprint: #{issue.fingerprint[0..16]}..."
      puts "    New fingerprint: #{new_fingerprint[0..16]}..."

      unless dry_run
        issue.update_column(:fingerprint, new_fingerprint)
      end

      stats[:updated] += 1
    end
  end
end
