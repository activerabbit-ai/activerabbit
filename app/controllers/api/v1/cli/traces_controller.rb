# frozen_string_literal: true

module Api
  module V1
    module Cli
      class TracesController < BaseController
        # GET /api/v1/cli/apps/:slug/traces
        # Trace analysis for an endpoint
        # Params: endpoint (e.g., "/jobs" or "JobsController#index")
        def index
          project = find_app_by_slug!(params[:slug])
          return unless project

          endpoint = params[:endpoint]

          unless endpoint.present?
            render json: { error: "bad_request", message: "endpoint parameter required" }, status: :bad_request
            return
          end

          # Find matching perf rollups for the endpoint
          # Try to match by target (controller#action) or by path
          rollups = find_rollups_for_endpoint(project, endpoint)

          if rollups.empty?
            render json: {
              error: "not_found",
              message: "No trace data found for endpoint: #{endpoint}"
            }, status: :not_found
            return
          end

          # Aggregate data
          total_duration = rollups.sum(:avg_duration_ms) / [rollups.count, 1].max
          p95_duration = rollups.average(:p95_duration_ms)&.round || 0

          # Build span breakdown from available data
          spans = build_spans(project, endpoint, rollups)

          # Identify bottlenecks
          bottlenecks = identify_bottlenecks(project, endpoint, spans)

          data = {
            trace_id: "tr_#{SecureRandom.hex(8)}",
            endpoint: endpoint,
            duration_ms: p95_duration,
            spans: spans,
            bottlenecks: bottlenecks
          }

          render_cli_response(command: "trace", data: data, project: project)
        end

        # GET /api/v1/cli/apps/:slug/traces/:id
        # Show specific trace (if we have trace IDs stored)
        def show
          project = find_app_by_slug!(params[:slug])
          return unless project

          # For now, return aggregated data for the most recent matching endpoint
          # In a full implementation, this would look up a specific trace by ID

          render json: {
            error: "not_implemented",
            message: "Individual trace lookup not yet implemented. Use endpoint-based trace: GET /api/v1/cli/apps/:slug/traces?endpoint=/path"
          }, status: :not_implemented
        end

        private

        def find_rollups_for_endpoint(project, endpoint)
          # Clean up the endpoint for matching
          target = endpoint.gsub(%r{^/}, "")  # Remove leading slash

          # Try exact match first
          rollups = project.perf_rollups
                           .where(timeframe: "minute")
                           .where("timestamp > ?", 1.hour.ago)
                           .where("target ILIKE ?", "%#{target}%")

          return rollups if rollups.any?

          # Try matching by path pattern
          # Convert /jobs/:id to match JobsController#show
          if endpoint.start_with?("/")
            controller_name = endpoint.split("/").reject(&:blank?).first&.singularize&.camelize
            if controller_name
              project.perf_rollups
                     .where(timeframe: "minute")
                     .where("timestamp > ?", 1.hour.ago)
                     .where("target ILIKE ?", "#{controller_name}Controller#%")
            else
              PerfRollup.none
            end
          else
            PerfRollup.none
          end
        end

        def build_spans(project, endpoint, rollups)
          spans = []

          # Main controller span
          avg_total = rollups.average(:avg_duration_ms)&.round || 0
          spans << {
            name: rollups.first&.target || endpoint,
            duration_ms: avg_total,
            percent: 100
          }

          # Check for N+1 queries in SQL fingerprints
          sql_time = estimate_sql_time(project, endpoint)
          if sql_time > 0
            sql_percent = [(sql_time.to_f / [avg_total, 1].max * 100).round, 100].min
            spans << {
              name: "SQL Queries",
              duration_ms: sql_time,
              percent: sql_percent
            }
          end

          # Check for N+1 issues
          n_plus_ones = project.sql_fingerprints
                               .where("created_at > ?", 24.hours.ago)
                               .where(severity: %w[high critical])
                               .limit(3)

          n_plus_ones.each do |fp|
            n1_time = fp.avg_duration_ms || 50
            n1_percent = [(n1_time.to_f / [avg_total, 1].max * 100).round, 50].min
            spans << {
              name: "N+1: #{fp.table_name || 'query'}",
              duration_ms: n1_time.round,
              percent: n1_percent
            }
          end

          spans.sort_by { |s| -s[:duration_ms] }
        end

        def estimate_sql_time(project, endpoint)
          # Estimate SQL time from SQL fingerprints or default to 60% of total
          fingerprints = project.sql_fingerprints.where("created_at > ?", 24.hours.ago)
          return 0 if fingerprints.empty?

          fingerprints.sum(:total_duration_ms).to_f / [fingerprints.sum(:call_count), 1].max
        end

        def identify_bottlenecks(project, endpoint, spans)
          bottlenecks = []

          # Check for N+1 queries
          n_plus_ones = project.sql_fingerprints
                               .where("created_at > ?", 24.hours.ago)
                               .where(severity: %w[high critical])

          if n_plus_ones.any?
            n_plus_ones.limit(2).each do |fp|
              bottlenecks << "N+1 query on #{fp.table_name || 'table'} (#{fp.call_count} calls)"
            end
          end

          # Check for slow average response
          avg_duration = spans.first&.dig(:duration_ms) || 0
          if avg_duration > 500
            bottlenecks << "Slow endpoint: #{avg_duration}ms average response time"
          end

          # Check for high error rate
          error_count = project.issues
                               .where("last_seen_at > ?", 1.hour.ago)
                               .where("controller_action ILIKE ?", "%#{endpoint.gsub('/', '')}%")
                               .count
          if error_count > 5
            bottlenecks << "High error rate: #{error_count} errors in the last hour"
          end

          bottlenecks << "No significant bottlenecks detected" if bottlenecks.empty?

          bottlenecks
        end
      end
    end
  end
end
