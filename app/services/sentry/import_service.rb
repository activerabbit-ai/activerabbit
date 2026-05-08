module Sentry
  class ImportService
    def self.call(project, days: 7, limit: 100)
      new(project, days: days, limit: limit).call
    end

    def initialize(project, days:, limit:)
      @project = project
      @days = days
      @limit = limit
    end

    def call
      token = @project.settings["sentry_auth_token"]
      org = @project.settings["sentry_org_slug"]
      proj = @project.settings["sentry_project_slug"]
      return { error: "missing_sentry_settings" } unless token && org && proj

      client = Sentry::Client.new(token)
      issues = client.list_issues(org: org, project_slug: proj, days: @days, limit: @limit)

      issues.each do |payload|
        issue = Sentry::EventMapper.upsert!(@project, payload)
        broadcast_imported(issue)
        # NOTE: do NOT enqueue AutoFixJob here — it's already triggered by AiSummaryJob
        # after the analyzer generates a summary. We just import; the existing pipeline
        # handles the rest.
      end

      stamp_completion!(issues.size)
      register_internal_integration!(client)
      broadcast_complete(issues.size)
      { imported: issues.size }
    end

    private

    def register_internal_integration!(client)
      return if @project.settings.to_h["sentry_internal_integration_uuid"].present?
      webhook_url = Rails.application.routes.url_helpers.sentry_webhook_url(
        project_id: @project.id,
        host: ENV.fetch("APP_HOST", "app.activerabbit.com"),
        protocol: "https"
      )
      result = client.register_internal_integration(
        org: @project.settings["sentry_org_slug"],
        webhook_url: webhook_url,
        name: "ActiveRabbit (#{@project.name})"
      )
      return if result[:integration_uuid].blank?
      settings = @project.settings.merge(
        "sentry_internal_integration_uuid" => result[:integration_uuid],
        "sentry_internal_integration_token" => result[:api_token]
      )
      @project.update!(settings: settings)
    end

    def stamp_completion!(count)
      settings = @project.settings || {}
      settings["sentry_initial_import_completed_at"] = Time.current.iso8601
      settings["sentry_initial_import_count"] = count
      @project.update!(settings: settings)
    end

    def broadcast_imported(issue)
      Turbo::StreamsChannel.broadcast_append_to(
        "project:#{@project.id}:onboarding",
        target: "status_rows",
        partial: "onboarding_wizard/status_row",
        locals: { kind: :issue_imported, issue: issue }
      )
    end

    def broadcast_complete(count)
      Turbo::StreamsChannel.broadcast_append_to(
        "project:#{@project.id}:onboarding",
        target: "status_rows",
        partial: "onboarding_wizard/status_row",
        locals: { kind: :import_complete, count: count }
      )
    end
  end
end
