module Sentry
  class IngestEventJob < ApplicationJob
    queue_as :default

    def perform(project_id, payload)
      project = ActsAsTenant.without_tenant { Project.find(project_id) }
      issue_data = payload.dig("data", "issue") || payload["issue"] || {}
      return if issue_data["id"].blank?

      mapped = {
        sentry_issue_id: issue_data["id"],
        title: issue_data["title"],
        culprit: issue_data["culprit"],
        exception_class: issue_data.dig("metadata", "type"),
        exception_message: issue_data.dig("metadata", "value"),
        permalink: issue_data["permalink"] || issue_data["web_url"],
        platform: issue_data["platform"] || project.settings.to_h["sentry_platform"],
        last_seen: issue_data["lastSeen"],
        event_count: issue_data["count"].to_i,
        user_count: issue_data["userCount"].to_i,
        raw: issue_data
      }

      ActsAsTenant.with_tenant(project.account) do
        Sentry::EventMapper.upsert!(project, mapped)
      end
    end
  end
end
