# frozen_string_literal: true

module SreInbox
  # Runs the SRE analyzer LLM over a single Issue and persists structured
  # results back onto the issue record.
  #
  # Usage:
  #   result = SreInbox::Analyzer.new(issue).call
  #   result[:ok]       # => true / false
  #   result[:analysis] # => parsed JSON hash matching sre_analyzer_prompt schema
  #
  # On success, the following Issue columns are updated:
  #   resolution_status, sre_confidence, root_cause (jsonb),
  #   fix_diff (text), safe_to_auto_merge (bool), sre_analyzed_at (datetime),
  #   sre_analysis (jsonb — full response blob for audit/replay).
  class Analyzer
    MODEL = "claude-haiku-4-5-20251001"
    MAX_TOKENS = 4000
    SAMPLE_EVENTS_LIMIT = 3
    RECENT_LOGS_LIMIT = 30
    RECENT_DEPLOYS_WINDOW = 2.hours
    SIMILAR_ISSUES_LIMIT = 3

    def initialize(issue, persist: true)
      @issue = issue
      @project = issue.project
      @persist = persist
    end

    def call
      return { ok: false, error: "missing_api_key" } if api_key.blank?

      payload = build_payload
      raw = invoke_llm(payload)
      analysis = parse_json(raw)

      persist!(analysis) if @persist

      { ok: true, analysis: analysis }
    rescue JSON::ParserError => e
      Rails.logger.error("[SreInbox::Analyzer] bad JSON: #{e.message}")
      { ok: false, error: "invalid_json", message: e.message }
    rescue => e
      Rails.logger.error("[SreInbox::Analyzer] #{e.class}: #{e.message}")
      { ok: false, error: "analyzer_error", message: e.message }
    end

    private

    def api_key
      ENV["ANTHROPIC_API_KEY"]
    end

    # ── Payload assembly ────────────────────────────────────────────────

    def build_payload
      {
        issue_id: @issue.id,
        error_class: @issue.exception_class,
        error_message: @issue.sample_message,
        controller_action: @issue.controller_action,
        top_frame: @issue.top_frame,
        stack_trace: sample_stack_trace,
        frequency: {
          total_occurrences: @issue.count,
          events_last_24h: safe_count { @issue.events_last_24h },
          window_start: @issue.first_seen_at&.iso8601,
          window_end: @issue.last_seen_at&.iso8601
        },
        first_seen: @issue.first_seen_at&.iso8601,
        last_seen: @issue.last_seen_at&.iso8601,
        affected_users: safe_count { @issue.unique_users_affected_24h },
        release: build_release,
        recent_deploys: build_recent_deploys,
        logs: build_logs,
        session_replays: build_replays,
        similar_issues: build_similar_issues,
        environment: build_environment,
        severity_hint: @issue.severity,
        source: @issue.source
      }.compact
    end

    def sample_stack_trace
      event = sample_event
      return nil unless event
      bt = event.backtrace.to_s
      return nil if bt.blank?
      bt.lines.first(30).join
    end

    def sample_event
      @sample_event ||= @issue.events.order(occurred_at: :desc).limit(1).first
    end

    def build_release
      event = sample_event
      return nil unless event
      {
        version: event.release_version,
        environment: event.environment,
        deploy_id: event.deploy_id
      }.compact.presence
    end

    def build_recent_deploys
      return [] unless @issue.first_seen_at && @project
      window_start = @issue.first_seen_at - RECENT_DEPLOYS_WINDOW
      Deploy.where(project_id: @project.id)
            .where(started_at: window_start..@issue.first_seen_at)
            .order(started_at: :desc)
            .limit(5)
            .map do |d|
              {
                id: d.id,
                status: d.status,
                started_at: d.started_at&.iso8601,
                version: d.release&.version
              }.compact
            end
    rescue ActiveRecord::StatementInvalid
      []
    end

    def build_logs
      return [] unless defined?(LogEntry)
      LogEntry.where(issue_id: @issue.id)
              .order(occurred_at: :desc)
              .limit(RECENT_LOGS_LIMIT)
              .map do |log|
                {
                  level: log.level,
                  message: redact(log.message),
                  occurred_at: log.occurred_at&.iso8601,
                  trace_id: log.trace_id
                }.compact
              end
    rescue ActiveRecord::StatementInvalid, NameError
      []
    end

    def build_replays
      return [] unless @issue.respond_to?(:replays)
      @issue.replays.limit(2).map do |r|
        {
          id: r.id,
          duration_ms: r.try(:duration_ms),
          started_at: r.try(:started_at)&.iso8601
        }.compact
      end
    rescue ActiveRecord::StatementInvalid
      []
    end

    def build_similar_issues
      return [] unless @project
      Issue.where(project_id: @project.id, exception_class: @issue.exception_class)
           .where.not(id: @issue.id)
           .order(last_seen_at: :desc)
           .limit(SIMILAR_ISSUES_LIMIT)
           .map do |sib|
             {
               id: sib.id,
               controller_action: sib.controller_action,
               status: sib.status,
               auto_fix_status: sib.auto_fix_status,
               closed_at: sib.closed_at&.iso8601
             }.compact
           end
    end

    def build_environment
      {
        rails_version: Rails.version,
        ruby_version: RUBY_VERSION,
        app_env: Rails.env
      }
    end

    # ── LLM call ────────────────────────────────────────────────────────

    def invoke_llm(payload)
      require "net/http"
      require "json"

      uri = URI.parse("https://api.anthropic.com/v1/messages")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      body = {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: SreAnalyzerPrompt::SYSTEM_PROMPT,
        messages: [
          { role: "user", content: SreAnalyzerPrompt.build_user_message(payload) }
        ]
      }

      req = Net::HTTP::Post.new(uri.request_uri)
      req["x-api-key"] = api_key
      req["anthropic-version"] = "2023-06-01"
      req["Content-Type"] = "application/json"
      req.body = JSON.dump(body)

      res = http.request(req)
      unless res.code.to_i.between?(200, 299)
        raise "Anthropic error #{res.code}: #{res.body[0, 500]}"
      end

      JSON.parse(res.body).dig("content", 0, "text").to_s
    end

    # ── Response parsing ────────────────────────────────────────────────

    # The prompt instructs the model to return bare JSON, but it sometimes
    # wraps output in ```json fences. Strip fences before parsing.
    def parse_json(raw)
      text = raw.strip
      if text.start_with?("```")
        text = text.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "")
      end
      JSON.parse(text)
    end

    # ── Persistence ─────────────────────────────────────────────────────

    def persist!(analysis)
      attrs = {
        resolution_status: analysis["resolution_status"],
        sre_confidence: safe_integer(analysis["confidence"]),
        root_cause: analysis["root_cause"],
        fix_diff: analysis.dig("fix", "diff"),
        safe_to_auto_merge: analysis.dig("fix", "safe_to_auto_merge"),
        sre_analyzed_at: Time.current,
        sre_analysis: analysis
      }
      @issue.update!(attrs.compact)
      reset_skipped_low_confidence_if_now_eligible
    end

    def reset_skipped_low_confidence_if_now_eligible
      return unless @issue.auto_fix_status == "skipped_low_confidence"
      project = @issue.project
      threshold = project.auto_pr_confidence_threshold.to_i
      return if @issue.sre_confidence.to_i < threshold
      @issue.update_columns(auto_fix_status: nil)
      AutoFixJob.perform_async(@issue.id, project.id)
    end

    # ── Helpers ─────────────────────────────────────────────────────────

    def safe_count
      yield
    rescue StandardError
      0
    end

    def safe_integer(val)
      Integer(val)
    rescue ArgumentError, TypeError
      nil
    end

    # Minimal redactor for obvious secrets in log lines before sending to LLM.
    # The prompt also instructs the model to redact — this is belt-and-suspenders.
    SECRET_PATTERNS = [
      /\b(?:password|passwd|secret|token|api[_-]?key|authorization)\s*[:=]\s*\S+/i,
      /\bBearer\s+[A-Za-z0-9\-_\.]+/,
      /\bsk-[A-Za-z0-9]{20,}/,
      /\b[A-Za-z0-9\-_]+@[A-Za-z0-9\-_\.]+\.[A-Za-z]{2,}\b/
    ].freeze

    def redact(str)
      return str if str.blank?
      SECRET_PATTERNS.reduce(str.dup) { |acc, re| acc.gsub(re, "[REDACTED]") }
    end
  end
end
