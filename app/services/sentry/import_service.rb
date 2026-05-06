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
      broadcast_complete(issues.size)
      { imported: issues.size }
    end

    private

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
