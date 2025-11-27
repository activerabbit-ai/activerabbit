require "redis"

class IssueAlertJob
  include Sidekiq::Job

  sidekiq_options queue: :alerts, retry: 2

  REDIS = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/1")

  def perform(issue_id, tenant_id)
    ActsAsTenant.with_tenant(Account.find(tenant_id)) do
      issue = Issue.find(issue_id)

      AlertRule.check_error_frequency_rules(issue)

      alert_key = "alert_sent:#{issue.project.id}:#{issue.fingerprint}:#{issue.controller_action}:#{Digest::MD5.hexdigest(issue.top_frame || '')}"

      unless redis_key_exists?(alert_key)
        issue.project.alert_rules.active.for_type("new_issue").each do |rule|
          AlertJob.perform_async(rule.id, "new_issue", { issue_id: issue.id })
        end

        mark_redis_key(alert_key)
      end
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Issue not found for alert: #{issue_id}"
  rescue => e
    Rails.logger.error "Error in issue alert job: #{e.message}"
    raise e
  end

  private

  def redis_key_exists?(key)
    REDIS.exists?(key)
  end

  def mark_redis_key(key)
    REDIS.set(key, true, ex: 3.days.to_i)
  end
end
