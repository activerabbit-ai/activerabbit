# frozen_string_literal: true

# Runs SreInbox::Analyzer against a single Issue and persists the result.
# Triggered:
#   * by ErrorIngestJob on the FIRST occurrence of a fingerprint (count == 1)
#     so the 19k pre-existing backlog is never auto-analyzed.
#   * manually from the backfill rake task for the most-recent N issues.
#
# Idempotent: skips if Issue#sre_analyzed_at is already set.
class AnalyzeIssueJob
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 3

  # Per-account hourly cap to bound runaway costs in production.
  HOURLY_QUOTA_PER_ACCOUNT = 50

  def perform(issue_id)
    issue = Issue.unscoped.find_by(id: issue_id)
    return Rails.logger.warn("[AnalyzeIssueJob] missing issue id=#{issue_id}") unless issue
    return if issue.sre_analyzed_at.present?  # already analyzed
    return Rails.logger.info("[AnalyzeIssueJob] no api key — skipping issue #{issue.id}") if ENV["ANTHROPIC_API_KEY"].blank?
    return Rails.logger.info("[AnalyzeIssueJob] over quota — skipping issue #{issue.id}") unless within_account_quota?(issue.account_id)

    SreInbox::Analyzer.new(issue).call
  end

  private

  def within_account_quota?(account_id)
    redis_key = "sre_inbox_analyzed:#{account_id}:#{Time.current.strftime('%Y-%m-%d-%H')}"
    count = Sidekiq.redis { |c| c.incr(redis_key) }
    Sidekiq.redis { |c| c.expire(redis_key, 2.hours.to_i) } if count == 1
    count <= HOURLY_QUOTA_PER_ACCOUNT
  end
end
