# frozen_string_literal: true

module Api
  module V1
    module Cli
      class IncidentsController < BaseController
        # GET /api/v1/cli/apps/:slug/incidents
        # List incidents (issues) for an app
        def index
          project = find_app_by_slug!(params[:slug])
          return unless project

          limit = (params[:limit] || 10).to_i.clamp(1, 100)

          issues = project.issues
                          .where(status: %w[open wip])
                          .order(last_seen_at: :desc)
                          .limit(limit)

          incidents = issues.map do |issue|
            {
              id: "inc_#{issue.id}",
              severity: calculate_severity(issue),
              title: issue.title,
              endpoint: format_endpoint(issue),
              count: issue.count,
              last_seen_at: issue.last_seen_at&.utc&.iso8601,
              first_seen_at: issue.first_seen_at&.utc&.iso8601,
              status: issue.status
            }
          end

          render_cli_response(command: "incidents", data: { incidents: incidents }, project: project)
        end

        # GET /api/v1/cli/apps/:slug/incidents/:id
        # Show incident detail
        def show
          project = find_app_by_slug!(params[:slug])
          return unless project

          issue = find_issue!(params[:id])
          return unless issue

          recent_events = issue.events.order(occurred_at: :desc).limit(5)

          data = {
            id: "inc_#{issue.id}",
            severity: calculate_severity(issue),
            status: issue.status,
            title: issue.title,
            exception_class: issue.exception_class,
            message: issue.sample_message,
            endpoint: format_endpoint(issue),
            count: issue.count,
            affected_users: issue.unique_users_affected_24h,
            first_seen_at: issue.first_seen_at&.utc&.iso8601,
            last_seen_at: issue.last_seen_at&.utc&.iso8601,
            top_frame: issue.top_frame,
            backtrace: extract_backtrace(issue),
            recent_events: recent_events.map do |event|
              {
                at: event.occurred_at&.utc&.iso8601,
                user_id: event.user_id_hash&.first(8),
                request_id: event.request_id
              }
            end,
            tags: extract_tags(issue)
          }

          render_cli_response(command: "incident_detail", data: data, project: project)
        end

        # GET /api/v1/cli/apps/:slug/incidents/:id/explain
        # AI-powered analysis
        def explain
          project = find_app_by_slug!(params[:slug])
          return unless project

          issue = find_issue!(params[:id])
          return unless issue

          # Check if we have a cached AI summary
          if issue.ai_summary.present? && issue.ai_summary_generated_at && issue.ai_summary_generated_at > 1.hour.ago
            # Use cached summary, parse it for structured response
            data = build_explain_from_cached(issue)
          else
            # Generate new AI summary
            sample_event = issue.events.order(occurred_at: :desc).first
            service = AiSummaryService.new(account: issue.account, issue: issue, sample_event: sample_event)
            result = service.call

            if result[:error]
              data = build_explain_fallback(issue, result[:message])
            else
              # Save the summary
              issue.update(ai_summary: result[:summary], ai_summary_generated_at: Time.current)
              data = build_explain_from_summary(issue, result[:summary])
            end
          end

          render_cli_response(command: "explain", data: data, project: project)
        end

        private

        def find_issue!(id)
          # Strip "inc_" prefix if present
          numeric_id = id.to_s.sub(/^inc_/, "")
          issue = Issue.find_by(id: numeric_id)

          unless issue
            render json: { error: "not_found", message: "Incident not found: #{id}" }, status: :not_found
            return nil
          end

          issue
        end

        def calculate_severity(issue)
          # Use stored severity if available, otherwise calculate
          return issue.severity if issue.respond_to?(:severity) && issue.severity.present?

          # Fallback calculation for issues without stored severity
          count_24h = issue.events_last_24h

          if count_24h > 100 || issue.count > 1000
            "critical"
          elsif count_24h > 20 || issue.count > 100
            "high"
          elsif count_24h > 5 || issue.count > 20
            "medium"
          else
            "low"
          end
        end

        def format_endpoint(issue)
          action = issue.controller_action
          return action unless action

          # Try to extract HTTP method from recent event
          recent_event = issue.events.order(occurred_at: :desc).first
          if recent_event&.request_method.present?
            "#{recent_event.request_method} #{recent_event.request_path || action}"
          else
            action
          end
        end

        def extract_backtrace(issue)
          recent_event = issue.events.order(occurred_at: :desc).first
          return [issue.top_frame].compact unless recent_event&.backtrace

          recent_event.formatted_backtrace.first(10)
        end

        def extract_tags(issue)
          recent_event = issue.events.order(occurred_at: :desc).first
          return {} unless recent_event&.context

          tags = recent_event.context["tags"] || {}
          tags["controller"] ||= issue.controller_action&.split("#")&.first
          tags["action"] ||= issue.controller_action&.split("#")&.last
          tags["environment"] ||= recent_event.environment
          tags.compact
        end

        def build_explain_from_cached(issue)
          summary = issue.ai_summary || ""

          # Parse markdown sections from AI summary
          root_cause = extract_section(summary, "Root Cause") || "See AI summary for details."
          suggested_fix = extract_section(summary, "Suggested Fix") || "See AI summary for details."

          {
            incident_id: "inc_#{issue.id}",
            severity: calculate_severity(issue),
            title: issue.title,
            root_cause: root_cause.strip,
            confidence_score: 0.85,
            affected_endpoints: [issue.controller_action].compact,
            suggested_fix: suggested_fix.strip,
            regression_risk: calculate_regression_risk(issue),
            tests_to_run: suggest_tests(issue),
            estimated_impact: estimate_impact(issue)
          }
        end

        def build_explain_from_summary(issue, summary)
          root_cause = extract_section(summary, "Root Cause") || "Analysis complete. See full summary."
          suggested_fix = extract_section(summary, "Suggested Fix") || "See full summary for fix details."

          {
            incident_id: "inc_#{issue.id}",
            severity: calculate_severity(issue),
            title: issue.title,
            root_cause: root_cause.strip,
            confidence_score: 0.87,
            affected_endpoints: [issue.controller_action].compact,
            suggested_fix: suggested_fix.strip,
            regression_risk: calculate_regression_risk(issue),
            tests_to_run: suggest_tests(issue),
            estimated_impact: estimate_impact(issue)
          }
        end

        def build_explain_fallback(issue, error_message)
          {
            incident_id: "inc_#{issue.id}",
            severity: calculate_severity(issue),
            title: issue.title,
            root_cause: "AI analysis unavailable: #{error_message}",
            confidence_score: 0.0,
            affected_endpoints: [issue.controller_action].compact,
            suggested_fix: "Manual investigation required. Check the stack trace and recent events.",
            regression_risk: "unknown",
            tests_to_run: suggest_tests(issue),
            estimated_impact: estimate_impact(issue)
          }
        end

        def extract_section(markdown, heading)
          # Extract content between ## Heading and next ## or end
          pattern = /##\s*#{Regexp.escape(heading)}\s*\n(.*?)(?=\n##|\z)/mi
          match = markdown.match(pattern)
          match ? match[1].strip : nil
        end

        def calculate_regression_risk(issue)
          # High risk if affects many users or is in critical path
          if issue.unique_users_affected_24h > 100
            "high"
          elsif issue.count > 50
            "medium"
          else
            "low"
          end
        end

        def suggest_tests(issue)
          tests = []
          action = issue.controller_action

          if action&.include?("Controller#")
            controller, method = action.split("#")
            controller_snake = controller.gsub(/Controller$/, "").underscore
            tests << "spec/requests/#{controller_snake}_spec.rb"
            tests << "spec/controllers/#{controller_snake}_controller_spec.rb"
            tests << "test/controllers/#{controller_snake}_controller_test.rb"
          elsif action # Job class
            job_snake = action.underscore
            tests << "spec/jobs/#{job_snake}_spec.rb"
            tests << "test/jobs/#{job_snake}_test.rb"
          end

          tests
        end

        def estimate_impact(issue)
          users = issue.unique_users_affected_24h
          count = issue.events_last_24h

          if users > 100 || count > 500
            "High impact: #{users} users affected, #{count} occurrences in 24h"
          elsif users > 10 || count > 50
            "Medium impact: #{users} users affected, #{count} occurrences in 24h"
          else
            "Low impact: #{users} users affected, #{count} occurrences in 24h"
          end
        end
      end
    end
  end
end
