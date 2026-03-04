# frozen_string_literal: true

# Recalculates severity for all active (open/wip) issues.
# Run periodically (every 5-10 minutes) to keep severity badges accurate.
#
# Severity is based on event counts in the last 24 hours:
#   - critical: >100 events/24h OR >1000 total
#   - high:     >20 events/24h OR >100 total
#   - medium:   >5 events/24h OR >20 total
#   - low:      everything else
#
class SeverityUpdateJob < ApplicationJob
  queue_as :default

  def perform
    # Process all accounts
    Account.find_each do |account|
      ActsAsTenant.with_tenant(account) do
        update_severities_for_account(account)
      end
    end
  end

  private

  def update_severities_for_account(account)
    # Only update open/wip issues (closed issues don't need severity updates)
    issues = Issue.where(status: %w[open wip])

    issues.find_each do |issue|
      new_severity = issue.calculated_severity
      if issue.severity != new_severity
        issue.update_column(:severity, new_severity)
        Rails.logger.info("[SeverityUpdateJob] Updated issue #{issue.id} severity: #{issue.severity} -> #{new_severity}")
      end
    end
  end
end
