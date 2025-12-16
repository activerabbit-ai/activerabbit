class IssueAlertJob
  include Sidekiq::Job
  sidekiq_options queue: :alerts, retry: 2

  REDIS = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/1")

  def perform(issue_id, tenant_id)
    ActsAsTenant.with_tenant(Account.find(tenant_id)) do
      issue = Issue.find(issue_id)

      # error frequency rules
      AlertRule.check_error_frequency_rules(issue)

      # new issue (dedup only)
      key = redis_key(issue)

      return if REDIS.exists?(key)

      issue.project.alert_rules.active.for_type("new_issue").each do |rule|
        AlertJob.perform_async(rule.id, "new_issue", { issue_id: issue.id })
      end

      REDIS.set(key, true, ex: 5.minutes.to_i)
    end
  end

  private

  def redis_key(issue)
    "issue_seen:#{issue.project_id}:#{issue.fingerprint}"
  end
end
