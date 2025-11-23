require "ostruct"

class PerformanceController < ApplicationController
  # Keep views under admin/performance
  layout "admin"
  before_action :authenticate_user!
  before_action :set_project, if: -> { params[:project_id] }

  def index
    # Use current_project from ApplicationController (set by slug) or @project (set by project_id)
    project_scope = @current_project || @project

    if project_scope
      # Single project performance view
      @timeframe = params[:timeframe] || "hour"
      # Adaptive default window so the page shows data by default
      requested_hours = (params[:hours_back] || 24).to_i
      @hours_back = requested_hours
      unless PerformanceEvent.where(project: project_scope).where("occurred_at > ?", @hours_back.hours.ago).exists?
        @hours_back = [@hours_back, 168].max # 7 days
      end
      unless PerformanceEvent.where(project: project_scope).where("occurred_at > ?", @hours_back.hours.ago).exists?
        @hours_back = [@hours_back, 720].max # 30 days
      end

      @rollups = project_scope.perf_rollups
                         .where(timeframe: @timeframe)
                         .where("timestamp > ?", @hours_back.hours.ago)
                         .order(:timestamp)

      # Group by target (controller action)
      @performance_data = @rollups.group_by(&:target)

      # N+1 queries
      @n_plus_one_incidents = project_scope.sql_fingerprints
                                     .n_plus_one_candidates
                                     .limit(20)

      # Slow queries
      @slow_queries = project_scope.sql_fingerprints
                              .slow
                              .limit(20)

      # Calculate project-specific metrics
      recent_rollups = project_scope.perf_rollups.where("timestamp > ?", @hours_back.hours.ago)
      raw_events_scope = PerformanceEvent.where(project: project_scope).where("occurred_at > ?", @hours_back.hours.ago)
      slow_threshold_ms = 1000

      if recent_rollups.exists?
      total_requests = recent_rollups.sum(:request_count)
      total_errors = recent_rollups.sum(:error_count)
      avg_response = recent_rollups.average(:avg_duration_ms)
        slow_requests = raw_events_scope.where("duration_ms > ?", slow_threshold_ms).count

        @metrics = {
          response_time: avg_response ? "#{avg_response.round(1)}ms" : "N/A",
          throughput: "#{total_requests}/day",
          error_rate: total_requests > 0 ? "#{((total_errors.to_f / total_requests) * 100).round(2)}%" : "0%",
          slow_requests: slow_requests
        }
      else
        # Fallback to raw events when rollups are not present
        total_requests = raw_events_scope.count
        avg_response = raw_events_scope.average(:duration_ms)
        slow_requests = raw_events_scope.where("duration_ms > ?", slow_threshold_ms).count

      @metrics = {
        response_time: avg_response ? "#{avg_response.round(1)}ms" : "N/A",
        throughput: "#{total_requests}/day",
          error_rate: total_requests > 0 ? "0.0%" : "0%",
          slow_requests: slow_requests
        }
      end

      # Build list rows: prefer rollups; fallback to raw events if no rollups present
      @list_rows = []
      if @rollups.exists?
        # Summarize by target from rollups
        rollup_groups = @rollups.group_by(&:target)

        # Optional: filter to only "slow" actions when requested
        if params[:filter] == "slow"
          slow_targets = rollup_groups.select do |_target, rows|
            avg_ms = rows.map(&:avg_duration_ms).compact
            p95_ms = rows.map(&:p95_duration_ms).compact
            avg_val = avg_ms.any? ? (avg_ms.sum / avg_ms.size.to_f).round(1) : nil
            p95_val = p95_ms.any? ? (p95_ms.sum / p95_ms.size.to_f).round(1) : nil
            (avg_val || 0) > 1000 || (p95_val || 0) > 1500
          end
          rollup_groups = slow_targets
        end

        rollup_groups.each do |target, rows|
          total_requests_t = rows.sum(&:request_count)
          total_errors_t = rows.sum(&:error_count)
          avg_ms = rows.map(&:avg_duration_ms).compact
          p95_ms = rows.map(&:p95_duration_ms).compact
          first_seen = rows.map(&:timestamp).min
          last_seen = rows.map(&:timestamp).max

          avg_val = avg_ms.any? ? (avg_ms.sum / avg_ms.size.to_f).round(1) : nil
          p95_val = p95_ms.any? ? (p95_ms.sum / p95_ms.size.to_f).round(1) : nil

          status = if total_errors_t.to_i > 0
                     "issues"
          elsif (avg_val || 0) > 1000 || (p95_val || 0) > 1500
                     "slow"
          else
                     "healthy"
          end

        @list_rows << {
          action: target,
          avg_response_time: avg_val ? "#{avg_val}ms" : "N/A",
          p95_response_time: p95_val ? "#{p95_val}ms" : "N/A",
          total_requests: total_requests_t,
          error_count: total_errors_t,
          status: status,
          first_seen: first_seen,
          last_seen: last_seen,
          github_pr_url: project_scope.settings&.dig("perf_pr_urls", target.to_s)
        }
        end
      else
        # Fallback: derive from raw performance events within window
        window_start = @hours_back.hours.ago
        events = PerformanceEvent.where(project: project_scope)
                                 .where("occurred_at > ?", window_start)

        event_groups = events.group_by(&:target)

        # Optional: filter to only "slow" actions when requested
        if params[:filter] == "slow"
          event_groups = event_groups.select do |_target, evts|
            durations = evts.map(&:duration_ms).compact
            avg_val = durations.any? ? (durations.sum / durations.size.to_f) : nil
            p95_val = if durations.any?
                        idx = (0.95 * (durations.size - 1)).round
                        durations[idx]
                      end
            (avg_val || 0) > 1000 || (p95_val || 0) > 1500
          end
        end

        event_groups.each do |target, evts|
          durations = evts.map(&:duration_ms).compact.sort
          avg_val = durations.any? ? (durations.sum / durations.size.to_f) : nil
          p95_val = if durations.any?
                      idx = (0.95 * (durations.size - 1)).round
                      durations[idx]
          end
          first_seen = evts.map(&:occurred_at).min
          last_seen = evts.map(&:occurred_at).max

          status = if (avg_val || 0) > 1000 || (p95_val || 0) > 1500
                     "slow"
          else
                     "healthy"
          end

        @list_rows << {
          action: target,
          avg_response_time: avg_val ? "#{avg_val.round(1)}ms" : "N/A",
          p95_response_time: p95_val ? "#{p95_val.round(1)}ms" : "N/A",
          total_requests: evts.size,
          error_count: 0,
          status: status,
          first_seen: first_seen,
          last_seen: last_seen,
          github_pr_url: project_scope.settings&.dig("perf_pr_urls", target.to_s)
        }
        end
        @list_rows.sort_by! { |r| -r[:total_requests].to_i }
      end

      if params[:q].present?
        query = params[:q].downcase
        @list_rows.select! { |row| row[:action].downcase.include?(query) }
      end

      if params[:sort].present?
        sort_key, sort_dir = params[:sort].split("_") # ex: "avg_response_time_desc"
        @list_rows.sort_by! do |row|
          value = row[sort_key.to_sym]
          if value.to_s.end_with?("ms")
            value.to_f
          else
            value.to_s.downcase
          end
        end
        @list_rows.reverse! if sort_dir == "desc"
      end

      # Paginate list_rows (array pagination)
      @pagy, @list_rows = pagy_array(@list_rows, limit: 50)

      # Optional Graph (counts over time) for Performance Events
      if params[:tab] == "graph"
        range_key = (params[:range] || "7D").to_s.upcase
        if range_key == "ALL"
          earliest = PerformanceEvent.where(project: project_scope).minimum(:occurred_at) ||
                     project_scope.perf_rollups.minimum(:timestamp)
          if earliest
            start_time = earliest
            end_time = Time.current
          span_seconds = (end_time - start_time).to_f
          if span_seconds <= 48.hours
            bucket_seconds = 5.minutes
          elsif span_seconds <= 30.days
            bucket_seconds = 1.day
          else
            bucket_seconds = 7.days
          end
            bucket_count = ((span_seconds / bucket_seconds).ceil).clamp(1, 300)
          else
            start_time = 7.days.ago
            end_time = Time.current
            bucket_seconds = 1.day
            bucket_count = 7
          end
        else
          window_seconds = case range_key
          when "1H" then 1.hour
          when "4H" then 4.hours
          when "8H" then 8.hours
          when "12H" then 12.hours
          when "24H" then 24.hours
          when "48H" then 48.hours
          when "7D" then 7.days
          when "30D" then 30.days
          else 7.days
          end

          bucket_seconds = case range_key
          when "1H", "4H", "8H" then 5.minutes
          when "12H" then 15.minutes
          when "24H", "48H" then 1.hour
          when "7D", "30D" then 1.day
          else 1.day
          end

          start_time = Time.current - window_seconds
          end_time = Time.current
          bucket_count = ((window_seconds.to_f / bucket_seconds).ceil).clamp(1, 300)
        end

        counts = Array.new(bucket_count, 0)
        labels = Array.new(bucket_count) { |i| start_time + i * bucket_seconds }

        event_times = PerformanceEvent.where(project: project_scope)
                                      .where("occurred_at >= ? AND occurred_at <= ?", start_time, end_time)
                                      .pluck(:occurred_at)
        event_times.each do |ts|
          idx = (((ts - start_time) / bucket_seconds).floor).to_i
          next if idx.negative? || idx >= bucket_count
          counts[idx] += 1
        end

        @graph_labels = labels
        @graph_counts = counts
        @graph_max = [counts.max || 0, 1].max
        @graph_has_data = counts.sum > 0
        @graph_range_key = range_key
      end
    else
      # Global performance overview
      @projects = current_user.projects.includes(:perf_rollups)

      @global_stats = {}
      total_requests = 0
      total_errors = 0
      response_times = []

      slow_threshold_ms = 1000
      slow_requests_sum = 0
      @projects.each do |project|
        recent_rollups = project.perf_rollups.where("timestamp > ?", 24.hours.ago)
        if recent_rollups.exists?
        avg_response = recent_rollups.average(:avg_duration_ms)
        requests = recent_rollups.sum(:request_count)
        errors = recent_rollups.sum(:error_count)
          p95 = recent_rollups.average(:p95_duration_ms)
        else
          raw_events = PerformanceEvent.where(project: project).where("occurred_at > ?", 24.hours.ago)
          avg_response = raw_events.average(:duration_ms)
          requests = raw_events.count
          errors = 0
          p95 = nil
        end

        slow_requests_sum += PerformanceEvent.where(project: project).where("occurred_at > ?", 24.hours.ago).where("duration_ms > ?", slow_threshold_ms).count

        @global_stats[project.id] = {
          avg_response_time: avg_response&.round(2),
          p95_response_time: p95&.round(2),
          total_requests: requests,
          error_count: errors
        }

        # Accumulate for global metrics
        total_requests += requests
        total_errors += errors
        response_times << avg_response if avg_response
      end

      # Calculate global metrics
      @metrics = {
        response_time: response_times.any? ? "#{(response_times.sum / response_times.size).round(1)}ms" : "N/A",
        throughput: "#{total_requests}/day",
        error_rate: total_requests > 0 ? "#{((total_errors.to_f / total_requests) * 100).round(2)}%" : "0%",
        slow_requests: slow_requests_sum
      }

      if params[:tab] == "graph"
        range_key = (params[:range] || "7D").to_s.upcase
        if range_key == "ALL"
          earliest = PerformanceEvent.minimum(:occurred_at) || PerfRollup.minimum(:timestamp)
          if earliest
            start_time = earliest
            end_time = Time.current
            span_seconds = (end_time - start_time).to_f
            if span_seconds <= 48.hours
              bucket_seconds = 5.minutes
            elsif span_seconds <= 30.days
              bucket_seconds = 1.day
            else
              bucket_seconds = 7.days
            end
            bucket_count = ((span_seconds / bucket_seconds).ceil).clamp(1, 300)
          else
            start_time = 7.days.ago
            end_time = Time.current
            bucket_seconds = 1.day
            bucket_count = 7
          end
        else
          window_seconds = case range_key
          when "1H" then 1.hour
          when "4H" then 4.hours
          when "8H" then 8.hours
          when "12H" then 12.hours
          when "24H" then 24.hours
          when "48H" then 48.hours
          when "7D" then 7.days
          when "30D" then 30.days
          else 7.days
          end

          bucket_seconds = case range_key
          when "1H", "4H", "8H" then 5.minutes
          when "12H" then 15.minutes
          when "24H", "48H" then 1.hour
          when "7D", "30D" then 1.day
          else 1.day
          end

          start_time = Time.current - window_seconds
          end_time = Time.current
          bucket_count = ((window_seconds.to_f / bucket_seconds).ceil).clamp(1, 300)
        end

        counts = Array.new(bucket_count, 0)
        labels = Array.new(bucket_count) { |i| start_time + i * bucket_seconds }

        event_times = PerformanceEvent.where("occurred_at >= ? AND occurred_at <= ?", start_time, end_time)
                                      .pluck(:occurred_at)
        event_times.each do |ts|
          idx = (((ts - start_time) / bucket_seconds).floor).to_i
          next if idx.negative? || idx >= bucket_count
          counts[idx] += 1
        end

        @graph_labels = labels
        @graph_counts = counts
        @graph_max = [counts.max || 0, 1].max
        @graph_has_data = counts.sum > 0
        @graph_range_key = range_key
      end
    end
  end

  def action_detail
    @target = params[:target]
    @current_tab = case params[:tab]
    when "samples" then "samples"
    when "graph" then "graph"
    when "ai" then "ai"
    else "summary"
    end

    # Range handling (default ALL except Graph which defaults to 7D)
    default_range_key = (@current_tab == "graph") ? "7D" : "ALL"
    range_key = (params[:range] || default_range_key).to_s.upcase
    window_seconds = case range_key
    when "1H" then 1.hour
    when "4H" then 4.hours
    when "8H" then 8.hours
    when "12H" then 12.hours
    when "24H" then 24.hours
    when "48H" then 48.hours
    when "7D" then 7.days
    when "30D" then 30.days
    when "ALL" then nil
    else 7.days
    end

    project_scope = @current_project || @project

    # Compute start_time if finite window
    start_time = window_seconds ? (Time.current - window_seconds) : nil

    # Try to find real rollups for this specific target
    rollups_scope = project_scope.perf_rollups.where(target: @target)
    rollups_scope = rollups_scope.where("timestamp > ?", start_time) if start_time
    @rollups = rollups_scope.order(:timestamp)

      if @rollups.empty?
        # Fallback: derive summary from raw events for this target (last 7 days)
        raw_events_scope = PerformanceEvent.where(project: project_scope, target: @target)
        raw_events_scope = raw_events_scope.where("occurred_at > ?", start_time) if start_time
        raw_events = raw_events_scope
        durations = raw_events.pluck(:duration_ms).compact.sort

        @total_requests = raw_events.count
        @total_errors = 0
        @avg_response_time = durations.any? ? (durations.sum / durations.size.to_f) : nil
        @p50_response_time = if durations.any?; durations[(0.50 * (durations.size - 1)).round]; end
        @p95_response_time = if durations.any?; durations[(0.95 * (durations.size - 1)).round]; end
        @p99_response_time = if durations.any?; durations[(0.99 * (durations.size - 1)).round]; end
        @min_response_time = durations.first
        @max_response_time = durations.last
        @error_rate = 0

        @hourly_data = {}
        @daily_data = {}

        # Build synthetic daily "rollups" for the Performance History table from raw events
        occurred_and_duration = PerformanceEvent.where(project: project_scope, target: @target)
                                                .yield_self { |rel| start_time ? rel.where("occurred_at > ?", start_time) : rel }
                                                .pluck(:occurred_at, :duration_ms)
        grouped = occurred_and_duration.group_by { |(ts, _)| ts.beginning_of_day }
        synthetic = []
        grouped.each do |day_ts, pairs|
          ds = pairs.map { |(_, d)| d.to_f }.compact.sort
          next if ds.empty?
          avg = ds.sum / ds.size.to_f
          p95 = ds[(0.95 * (ds.size - 1)).round]
          synthetic << OpenStruct.new(
            id: synthetic.size + 1,
            timestamp: day_ts,
            avg_duration_ms: avg,
            p95_duration_ms: p95,
            request_count: ds.size,
            error_count: 0
          )
        end
        @rollups = synthetic.sort_by(&:timestamp)
      else
      # Calculate detailed metrics from rollups
      @total_requests = @rollups.sum(:request_count)
      @total_errors = @rollups.sum(:error_count)
      @avg_response_time = @rollups.average(:avg_duration_ms)
      @p50_response_time = @rollups.average(:p50_duration_ms)
      @p95_response_time = @rollups.average(:p95_duration_ms)
      @p99_response_time = @rollups.average(:p99_duration_ms)
      @min_response_time = @rollups.minimum(:min_duration_ms)
      @max_response_time = @rollups.maximum(:max_duration_ms)
      @error_rate = @total_requests > 0 ? ((@total_errors.to_f / @total_requests) * 100).round(2) : 0

      # Group by timeframe for charts
      @hourly_data = @rollups.where("timestamp > ?", 24.hours.ago)
                             .group_by { |r| r.timestamp.beginning_of_hour }

      @daily_data = @rollups.group_by { |r| r.timestamp.beginning_of_day }
      end


    # Common: recent samples for this action
    project_scope = @current_project || @project
    events_scope = PerformanceEvent.where(project: project_scope, target: @target)
    events_scope = events_scope.where("occurred_at > ?", start_time) if start_time
    @events = events_scope
                              .order(occurred_at: :desc)
                              .limit(200)
    if params[:event_id].present?
      @selected_event = @events.find { |e| e.id.to_s == params[:event_id].to_s }
    end
    @selected_event ||= @events.first

    # Graph data for this action
    if @current_tab == "graph"
      range_key = (params[:range] || "7D").to_s.upcase
      if range_key == "ALL"
        earliest = PerformanceEvent.where(project: project_scope, target: @target).minimum(:occurred_at) ||
                   project_scope.perf_rollups.where(target: @target).minimum(:timestamp)
        if earliest
          start_time = earliest
          end_time = Time.current
          span_seconds = (end_time - start_time).to_f
          # Choose bucket size based on span (cap buckets to 300)
          if span_seconds <= 48.hours
            bucket_seconds = 5.minutes
          elsif span_seconds <= 30.days
            bucket_seconds = 1.day
          else
            bucket_seconds = 7.days
          end
          bucket_count = ((span_seconds / bucket_seconds).ceil).clamp(1, 300)
        else
          # No data, fall back to 7D empty graph
          start_time = 7.days.ago
          end_time = Time.current
          bucket_seconds = 1.day
          bucket_count = 7
        end
      else
        window_seconds = case range_key
        when "1H" then 1.hour
        when "4H" then 4.hours
        when "8H" then 8.hours
        when "12H" then 12.hours
        when "24H" then 24.hours
        when "48H" then 48.hours
        when "7D" then 7.days
        when "30D" then 30.days
        else 24.hours
        end

        bucket_seconds = case range_key
        when "1H", "4H", "8H" then 5.minutes
        when "12H" then 15.minutes
        when "24H", "48H" then 1.hour
        when "7D", "30D" then 1.day
        else 1.hour
        end

        start_time = Time.current - window_seconds
        end_time = Time.current
        bucket_count = ((window_seconds.to_f / bucket_seconds).ceil).clamp(1, 300)
      end

      counts = Array.new(bucket_count, 0)
      labels = Array.new(bucket_count) { |i| start_time + i * bucket_seconds }

      events = PerformanceEvent.where(project: project_scope, target: @target)
                               .where("occurred_at >= ? AND occurred_at <= ?", start_time, end_time)
                               .pluck(:occurred_at, :duration_ms)
      sum_per_bucket = Array.new(bucket_count, 0.0)
      count_per_bucket = Array.new(bucket_count, 0)
      events.each do |ts, dur|
        idx = (((ts - start_time) / bucket_seconds).floor).to_i
        next if idx.negative? || idx >= bucket_count
        counts[idx] += 1
        if dur
          sum_per_bucket[idx] += dur.to_f
          count_per_bucket[idx] += 1
        end
      end

      @graph_labels = labels
      @graph_counts = counts
      @graph_max = [counts.max || 0, 1].max
      @graph_has_data = counts.sum > 0
      @graph_range_key = range_key

      # Additional series: average response time per bucket (ms)
      @graph_avg_ms = sum_per_bucket.each_with_index.map { |s, i| count_per_bucket[i] > 0 ? (s / count_per_bucket[i]).round(1) : 0 }
    end

    # AI summary generation on demand
    if @current_tab == "ai"
      summary_record = PerformanceSummary.find_by(project: project_scope, target: @target)
      if summary_record&.summary.present?
        @performance_summary = summary_record.summary
        @ai_result = { summary: @performance_summary }
        return
      end

      stats = {
        total_requests: @total_requests,
        total_errors: @total_errors,
        error_rate: @error_rate,
        avg_ms: (@avg_response_time&.round(1)),
        p95_ms: (@p95_response_time&.round(1))
      }
      sample = @selected_event || @events.first
      result = AiPerformanceSummaryService.new(target: @target, stats: stats, sample_event: sample).call

      if result[:summary].present?
        @performance_summary = result[:summary]
        @ai_result = result
        PerformanceSummary.find_or_initialize_by(project: project_scope, target: @target).tap do |record|
          record.account = project_scope.account
          record.summary = result[:summary]
          record.generated_at = Time.current
          record.save!
        end
      else
        @ai_result = result
      end
    end
  end

  # Show a specific performance issue by numeric id
  def show
    project_scope = @current_project || @project
    hours = (params[:hours_back] || 24).to_i
    window_start = hours.hours.ago

    # Order actions by recent volume (last hours), descending
    action_counts = PerformanceEvent.where(project: project_scope)
                                    .where("occurred_at > ?", window_start)
                                    .group(:target)
                                    .count
    ordered_targets = action_counts.sort_by { |_, c| -c }.map(&:first)

    idx = params[:id].to_i - 1
    if idx < 0 || idx >= ordered_targets.length
      redirect_path = if @current_project
                        "/#{@current_project.slug}/performance"
      elsif @project
                        project_performance_path(@project)
      else
                        performance_path
      end
      redirect_to redirect_path, alert: "Performance issue not found"
      return
    end

    target = ordered_targets[idx]

    # Redirect to canonical slug-based URL for action details, preserving context params
    redirect_path = if @current_project
                      project_slug_performance_action_detail_path(
                        @current_project.slug,
                        target: target,
                        tab: params[:tab],
                        range: params[:range],
                        event_id: params[:event_id]
                      )
    elsif @project
                      project_performance_action_detail_path(
                        @project,
                        target: target,
                        tab: params[:tab],
                        range: params[:range],
                        event_id: params[:event_id]
                      )
    else
                      performance_action_detail_path(
                        target: target,
                        tab: params[:tab],
                        range: params[:range],
                        event_id: params[:event_id]
                      )
    end

    redirect_to redirect_path and return
  end

  def sql_fingerprints
    project_scope = @current_project || @project
    scope = project_scope.sql_fingerprints.includes(:project)

    # Filtering
    case params[:filter]
    when "slow"
      scope = scope.slow
    when "frequent"
      scope = scope.frequent
    when "n_plus_one"
      scope = scope.n_plus_one_candidates
    end

    @pagy, @sql_fingerprints = pagy(scope, limit: 25)
  end

  def sql_fingerprint
    project_scope = @current_project || @project
    @sql_fingerprint = project_scope.sql_fingerprints.find(params[:id])
    @recent_events = project_scope.events
                             .where("payload->>'sql_queries' IS NOT NULL")
                             .where("created_at > ?", 7.days.ago)
                             .limit(50)
  end

  def create_pr
    project_scope = @current_project || @project
    target = params[:target]

    pr_service = GithubPrService.new(project_scope)
    # Build a pseudo-issue for performance with minimal attributes used by service body
    issue_like = OpenStruct.new(
      id: "perf-#{target.gsub(/[^a-zA-Z0-9_-]/, '-')}",
      exception_class: "Performance: #{target}",
      ai_summary: "Auto-detected performance regression for #{target}."
    )

    result = pr_service.create_pr_for_issue(issue_like)

    redirect_path = if @current_project
                      performance_action_detail_path(target: target)
    elsif @project
                      project_performance_action_detail_path(@project, target: target)
    else
                      performance_action_detail_path(target: target)
    end

    if result[:success]
      # Persist PR URL for this performance target to show a direct link next time
      pr_project = project_scope
      if pr_project
        settings = pr_project.settings || {}
        perf_pr_urls = settings["perf_pr_urls"] || {}
        perf_pr_urls[target.to_s] = result[:pr_url]
        settings["perf_pr_urls"] = perf_pr_urls
        pr_project.update(settings: settings)
      end

      redirect_to result[:pr_url], allow_other_host: true
    else
      redirect_to redirect_path, alert: (result[:error] || "Failed to open PR")
    end
  end

  def create_n_plus_one_pr
    project_scope = @current_project || @project
    @sql_fingerprint = project_scope.sql_fingerprints.find(params[:id])

    # This is a stub for GitHub integration
    # In a real implementation, this would create a PR with optimization suggestions

    pr_service = GithubPrService.new(project_scope)
    result = pr_service.create_n_plus_one_fix_pr(@sql_fingerprint)

    if result[:success]
      redirect_path = if @current_project
                        "/#{@current_project.slug}/performance/sql_fingerprints/#{@sql_fingerprint.id}"
      else
                        project_performance_sql_fingerprint_path(@project, @sql_fingerprint)
      end
      redirect_to redirect_path, notice: "PR created: #{result[:pr_url]}"
    else
      redirect_path = if @current_project
                        "/#{@current_project.slug}/performance/sql_fingerprints/#{@sql_fingerprint.id}"
      else
                        project_performance_sql_fingerprint_path(@project, @sql_fingerprint)
      end
      redirect_to redirect_path, alert: "Failed to create PR: #{result[:error]}"
    end
  end

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end
end
