class IssueAlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 2

  def perform(issue_id)
    issue = Issue.find(issue_id)

    # Check if this is a new issue
    if issue.count == 1
      # New issue alert
      AlertRule.check_error_frequency_rules(issue)

      # Also trigger new issue alerts if configured
      issue.project.alert_rules.active.for_type('new_issue').each do |rule|
        AlertJob.perform_async(rule.id, 'new_issue', { issue_id: issue.id })
      end
    else
      # Check frequency-based rules
      AlertRule.check_error_frequency_rules(issue)
    end

  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Issue not found for alert: #{issue_id}"
  rescue => e
    Rails.logger.error "Error in issue alert job: #{e.message}"
    raise e
  end
end
