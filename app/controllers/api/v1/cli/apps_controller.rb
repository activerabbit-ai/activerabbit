# frozen_string_literal: true

module Api
  module V1
    module Cli
      class AppsController < BaseController
        # GET /api/v1/cli/apps
        # List all apps (projects) accessible via current token
        def index
          apps = Project.active.order(:name).map do |project|
            {
              slug: project.slug,
              name: project.name,
              environment: project.environment,
              error_count_24h: project.issues.where("last_seen_at > ?", 24.hours.ago).sum(:count)
            }
          end

          render_cli_response(command: "apps", data: { apps: apps })
        end

        # GET /api/v1/cli/apps/:slug/status
        # Health snapshot for a single app
        def status
          project = find_app_by_slug!(params[:slug])
          return unless project

          error_count_24h = project.events.where("occurred_at > ?", 24.hours.ago).count

          # Calculate p95 latency from recent perf rollups
          recent_rollups = project.perf_rollups
                                  .where(timeframe: "minute")
                                  .where("timestamp > ?", 1.hour.ago)
          p95_latency_ms = if recent_rollups.any?
                             recent_rollups.average(:p95_duration_ms)&.round || 0
          else
                             0
          end

          # Deploy status
          last_deploy = project.deploys.order(created_at: :desc).first
          deploy_status = determine_deploy_status(project, last_deploy)

          # Top issue
          top_issue = project.issues.open.order(count: :desc).first

          data = {
            app: project.slug,
            name: project.name,
            health: project.computed_health_status,
            error_count_24h: error_count_24h,
            p95_latency_ms: p95_latency_ms,
            deploy_status: deploy_status,
            last_deploy_at: last_deploy&.created_at&.utc&.iso8601,
            top_issue: top_issue ? {
              id: "inc_#{top_issue.id}",
              title: top_issue.title,
              count: top_issue.count,
              severity: calculate_severity(top_issue)
            } : nil
          }

          render_cli_response(command: "status", data: data, project: project)
        end

        # GET /api/v1/cli/apps/:slug/deploy_check
        # Check if safe to deploy
        def deploy_check
          project = find_app_by_slug!(params[:slug])
          return unless project

          last_deploy = project.deploys.order(created_at: :desc).first
          new_errors_since_deploy = if last_deploy
                                      project.issues.where("first_seen_at > ?", last_deploy.created_at).count
          else
                                      0
          end

          warnings = []

          # Check for recent critical issues
          critical_issues = project.issues.open.where("last_seen_at > ?", 1.hour.ago).where("count > ?", 50)
          if critical_issues.any?
            warnings << "#{critical_issues.count} high-frequency issues in the last hour"
          end

          # Check for performance degradation
          recent_p95 = project.perf_rollups
                              .where(timeframe: "minute")
                              .where("timestamp > ?", 30.minutes.ago)
                              .average(:p95_duration_ms)
          if recent_p95 && recent_p95 > 1000
            warnings << "p95 latency is #{recent_p95.round}ms (above 1000ms threshold)"
          end

          ready = warnings.empty?

          data = {
            ready: ready,
            last_deploy_at: last_deploy&.created_at&.utc&.iso8601,
            new_errors_since_deploy: new_errors_since_deploy,
            warnings: warnings
          }

          render_cli_response(command: "deploy_check", data: data, project: project)
        end

        private

        def determine_deploy_status(project, last_deploy)
          return "unknown" unless last_deploy

          # Check for errors since deploy
          errors_since_deploy = project.issues.where("first_seen_at > ?", last_deploy.created_at).count

          if errors_since_deploy > 10
            "regression"
          elsif errors_since_deploy > 0
            "warning"
          else
            "stable"
          end
        end

        def calculate_severity(issue)
          # Use stored severity if available, otherwise calculate
          return issue.severity if issue.respond_to?(:severity) && issue.severity.present?

          # Fallback calculation for issues without stored severity
          count_24h = issue.events.where("occurred_at > ?", 24.hours.ago).count

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
      end
    end
  end
end
