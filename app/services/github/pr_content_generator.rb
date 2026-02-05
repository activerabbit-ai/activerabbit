# frozen_string_literal: true

module Github
  # Generates PR content (title, body, code fix) using AI or existing summaries
  class PrContentGenerator
    def initialize(anthropic_key: nil)
      @anthropic_key = anthropic_key || ENV["ANTHROPIC_API_KEY"]
    end

    def generate(issue)
      sample_event = issue.events.order(occurred_at: :desc).first

      # If we have existing AI summary, parse it for the fix section
      if issue.ai_summary.present?
        parsed = parse_ai_summary(issue.ai_summary)
        title = generate_pr_title(issue, parsed[:root_cause])
        body = build_enhanced_pr_body(issue, sample_event, parsed)
        code_fix = parsed[:fix_code]
        before_code = parsed[:before_code]

        { 
          title: title, 
          body: body, 
          code_fix: code_fix, 
          before_code: before_code,
          file_fixes: parsed[:file_fixes],
          related_changes: parsed[:related_changes]
        }
      elsif @anthropic_key.present?
        # Generate fresh AI analysis for the PR
        ai_result = generate_ai_pr_analysis(issue, sample_event)
        title = ai_result[:title] || "Fix #{issue.exception_class} in #{issue.controller_action}"
        body = ai_result[:body] || build_basic_pr_body(issue, sample_event)
        code_fix = ai_result[:code_fix]

        { title: title, body: body, code_fix: code_fix, file_fixes: [], related_changes: nil }
      else
        # Fallback to basic content
        {
          title: "Fix #{issue.exception_class} in #{issue.controller_action}",
          body: build_basic_pr_body(issue, sample_event),
          code_fix: nil,
          file_fixes: [],
          related_changes: nil
        }
      end
    end

    private

    def generate_pr_title(issue, root_cause)
      # Create a concise, descriptive title based on the root cause
      if root_cause.present?
        # Extract first sentence of root cause for title
        short_cause = root_cause.split(/[.\n]/).first.to_s.strip
        if short_cause.length > 60
          short_cause = short_cause[0, 57] + "..."
        end
        "fix: #{short_cause}"
      else
        "fix: #{issue.exception_class} in #{issue.controller_action.to_s.split('#').last}"
      end
    end

    def parse_ai_summary(summary)
      result = { root_cause: nil, fix: nil, fix_code: nil, before_code: nil, prevention: nil, file_fixes: [], related_changes: nil }
      return result if summary.blank?

      # Parse markdown sections from AI summary
      sections = summary.split(/^##\s+/m)

      sections.each do |section|
        if section.start_with?("Root Cause")
          result[:root_cause] = section.sub(/^Root Cause\s*\n/, "").strip
        elsif section.start_with?("Suggested Fix") || section.start_with?("Fix")
          fix_content = section.sub(/^(?:Suggested )?Fix\s*\n/, "").strip
          result[:fix] = fix_content

          Rails.logger.info "[GitHub API] Fix section content (first 500 chars): #{fix_content[0..500]}"

          # Check for multi-file format: "### File N:" sections
          if fix_content =~ /###\s+File\s+\d+:/i
            result[:file_fixes] = parse_multi_file_fixes(fix_content)
            Rails.logger.info "[GitHub API] Parsed #{result[:file_fixes].size} file fixes from multi-file format"
            
            # For backward compatibility, use the first file's fix as the primary fix
            if result[:file_fixes].any?
              first_fix = result[:file_fixes].first
              result[:fix_code] = first_fix[:after_code]
              result[:before_code] = first_fix[:before_code]
            end
          else
            # Single-file format (legacy)
            parsed = parse_single_file_fix(fix_content)
            result[:fix_code] = parsed[:fix_code]
            result[:before_code] = parsed[:before_code]
            
            # Extract file path if present
            if fix_content =~ /\*\*File:\*\*\s*`([^`]+)`/
              file_path = $1
              result[:file_fixes] << {
                file_path: file_path,
                before_code: result[:before_code],
                after_code: result[:fix_code]
              }
            end
          end
        elsif section.start_with?("Prevention")
          result[:prevention] = section.sub(/^Prevention\s*\n/, "").strip
        elsif section.start_with?("Related Changes")
          result[:related_changes] = section.sub(/^Related Changes\s*\n/, "").strip
        end
      end

      result
    end

    # Parse multiple file fixes from "### File N:" format
    # Safety limit: max 3 files (AiSummaryService::MAX_FILES_PER_FIX)
    def parse_multi_file_fixes(fix_content)
      file_fixes = []
      max_files = AiSummaryService::MAX_FILES_PER_FIX
      
      # Split by "### File N:" headers
      file_sections = fix_content.split(/(?=###\s+File\s+\d+:)/i)
      
      file_sections.each do |file_section|
        # Safety limit check
        if file_fixes.size >= max_files
          Rails.logger.warn "[GitHub API] Reached max file limit (#{max_files}), skipping remaining file fixes"
          break
        end
        
        next unless file_section =~ /###\s+File\s+\d+:\s*`([^`]+)`/i
        
        file_path = $1
        Rails.logger.info "[GitHub API] Parsing fix for file: #{file_path}"
        
        # Extract before and after code blocks
        parsed = parse_single_file_fix(file_section)
        
        if parsed[:fix_code].present?
          file_fixes << {
            file_path: file_path,
            before_code: parsed[:before_code],
            after_code: parsed[:fix_code]
          }
        end
      end
      
      file_fixes
    end

    # Parse a single file fix section (before/after code blocks)
    def parse_single_file_fix(fix_content)
      result = { fix_code: nil, before_code: nil }
      
      # Extract code blocks from the fix section with their positions
      code_block_matches = fix_content.to_enum(:scan, /```(?:ruby|rb)?\s*(.*?)```/m).map do
        [Regexp.last_match.begin(0), Regexp.last_match[1]]
      end

      code_blocks = code_block_matches.map { |_, code| code }

      return result unless code_blocks.any?

      # Find "Before" and "After" blocks
      raw_code = nil
      before_code = nil
      
      code_block_matches.each_with_index do |(position, block), idx|
        block_text = block.strip
        context_start = [0, position - 200].max
        context_before = fix_content[context_start..position].to_s.downcase

        # Check if this is "Before" block
        is_before_block = context_before =~ /(?:^|\n)\s*\*\*before\*\*|\*\*before\*\*|before:/i
        if is_before_block && before_code.nil?
          before_code = block_text
        end

        # Check if this block is marked as "After"
        is_after_block = context_before =~ /(?:^|\n)\s*\*\*after\*\*|\*\*after\*\*|after:|after\s+code|fixed\s+code|correct\s+code|solution/i
        if is_after_block
          raw_code = block_text
          break
        end
      end

      result[:before_code] = before_code if before_code.present?

      # If no "After" block found, use the last block
      if raw_code.nil? && code_blocks.size >= 2
        # Assume first block is "Before", last is "After"
        result[:before_code] ||= code_blocks.first.strip
        raw_code = code_blocks.last.strip
      elsif raw_code.nil? && code_blocks.size == 1
        raw_code = code_blocks.first.strip
      end

      if raw_code.present?
        extracted = extract_method_from_code(raw_code)
        result[:fix_code] = extracted || raw_code
      end

      result
    end

    def extract_method_from_code(code)
      return nil if code.blank?

      lines = code.lines
      return code if lines.size < 3 # Too short to have class/module

      # Check if code contains class/module definitions
      has_class_or_module = code =~ /^\s*(class|module)\s/

      # If no class/module, return as-is (might be just a method)
      return code unless has_class_or_module

      # Find the first method definition
      method_start = nil
      lines.each_with_index do |line, idx|
        if line =~ /^\s*def\s/
          method_start = idx
          break
        end
      end

      return code unless method_start # No method found, return original

      # Find method end
      method_end = method_start
      indent_level = lines[method_start].match(/^(\s*)/)[1].length

      (method_start + 1).upto(lines.size - 1) do |i|
        line = lines[i]
        line_indent = line.match(/^(\s*)/)[1].length

        # If we find an "end" at the same or less indentation, it's the method end
        if line.strip == "end" && line_indent <= indent_level
          method_end = i
          break
        end
      end

      # Extract method lines
      method_lines = lines[method_start..method_end] || []
      extracted = method_lines.join

      # Validate it's a complete method
      if validate_method_structure(extracted)
        Rails.logger.info "[GitHub API] Extracted method from code block (removed class/module wrapper)"
        extracted
      else
        # If extraction failed, return original
        code
      end
    end

    def build_enhanced_pr_body(issue, sample_event, parsed)
      lines = []

      # Header with issue link
      lines << "## 🐛 Bug Fix: #{issue.exception_class}"
      lines << ""
      lines << "**Issue ID:** ##{issue.id}"
      lines << "**Controller:** `#{issue.controller_action}`"
      lines << "**Occurrences:** #{issue.count} times"
      lines << "**First seen:** #{issue.first_seen_at&.strftime('%Y-%m-%d %H:%M')}"
      lines << "**Last seen:** #{issue.last_seen_at&.strftime('%Y-%m-%d %H:%M')}"
      lines << ""

      # Root Cause Analysis
      lines << "## 🔍 Root Cause Analysis"
      lines << ""
      if parsed[:root_cause].present?
        lines << parsed[:root_cause]
      else
        lines << "Analysis pending. Please review the stack trace below."
      end
      lines << ""

      # The Fix
      lines << "## 🔧 Suggested Fix"
      lines << ""
      if parsed[:fix].present?
        lines << parsed[:fix]
      else
        lines << "Manual review required. See error context below."
      end
      lines << ""

      # Related Changes (additional files that may need attention)
      if parsed[:related_changes].present?
        lines << "## ⚠️ Related Changes (Manual Review Required)"
        lines << ""
        lines << "> **Note:** This PR only fixes the primary error file. The following additional changes may be needed and should be applied locally before merging:"
        lines << ""
        lines << parsed[:related_changes]
        lines << ""
      end

      # Error Context
      lines << "## 📋 Error Details"
      lines << ""
      lines << "**Error Message:**"
      lines << "```"
      lines << (issue.sample_message.presence || "No message available")
      lines << "```"
      lines << ""

      # Stack trace
      if sample_event&.formatted_backtrace&.any?
        lines << "**Stack Trace (top frames):**"
        lines << "```"
        sample_event.formatted_backtrace.first(10).each { |frame| lines << frame }
        lines << "```"
        lines << ""
      end

      # Request context
      if sample_event
        lines << "**Request Context:**"
        lines << "- Method: `#{sample_event.request_method || 'N/A'}`"
        lines << "- Path: `#{sample_event.request_path || 'N/A'}`"
        lines << ""
      end

      # Prevention tips
      if parsed[:prevention].present?
        lines << "## 🛡️ Prevention"
        lines << ""
        lines << parsed[:prevention]
        lines << ""
      end

      # Checklist
      lines << "## ✅ Checklist"
      lines << ""
      lines << "- [ ] Code fix implemented"
      lines << "- [ ] Tests added/updated"
      lines << "- [ ] Error scenario manually verified"
      lines << "- [ ] No regressions introduced"
      lines << ""
      lines << "---"
      lines << "_Generated by [ActiveRabbit](https://activerabbit.ai) AI_"

      lines.join("\n")
    end

    def build_basic_pr_body(issue, sample_event)
      lines = []

      lines << "## 🐛 Bug Fix: #{issue.exception_class}"
      lines << ""
      lines << "**Issue ID:** ##{issue.id}"
      lines << "**Controller:** `#{issue.controller_action}`"
      lines << ""

      lines << "### Error Message"
      lines << "```"
      lines << (issue.sample_message.presence || "No message available")
      lines << "```"
      lines << ""

      if sample_event&.formatted_backtrace&.any?
        lines << "### Stack Trace"
        lines << "```"
        sample_event.formatted_backtrace.first(10).each { |frame| lines << frame }
        lines << "```"
        lines << ""
      end

      lines << "### Checklist"
      lines << "- [ ] Investigate root cause"
      lines << "- [ ] Implement fix"
      lines << "- [ ] Add tests"
      lines << ""
      lines << "---"
      lines << "_Generated by [ActiveRabbit](https://activerabbit.ai)_"

      lines.join("\n")
    end

    def generate_ai_pr_analysis(issue, sample_event)
      return {} unless @anthropic_key.present?

      prompt = build_pr_prompt(issue, sample_event)

      begin
        response = claude_chat_completion(prompt)
        parse_ai_pr_response(response, issue, sample_event)
      rescue => e
        Rails.logger.error "[GitHub PR] AI analysis failed: #{e.message}"
        {}
      end
    end

    def build_pr_prompt(issue, sample_event)
      parts = []
      parts << "You are helping create a GitHub Pull Request to fix a bug."
      parts << ""
      parts << "Error: #{issue.exception_class}"
      parts << "Message: #{issue.sample_message}"
      parts << "Location: #{issue.controller_action}"
      parts << "Top frame: #{issue.top_frame}"

      if sample_event&.has_structured_stack_trace?
        parts << ""
        parts << "Source code context:"
        sample_event.structured_stack_trace.select { |f| f["in_app"] }.first(3).each do |frame|
          ctx = frame["source_context"]
          if ctx
            parts << "File: #{frame['file']}:#{frame['line']}"
            (ctx["lines_before"] || []).each { |l| parts << "  #{l}" }
            parts << ">>> #{ctx['line_content']} # ERROR LINE"
            (ctx["lines_after"] || []).each { |l| parts << "  #{l}" }
            parts << ""
          end
        end
      elsif sample_event&.formatted_backtrace&.any?
        parts << ""
        parts << "Stack trace:"
        sample_event.formatted_backtrace.first(10).each { |line| parts << "  #{line}" }
      end

      parts << ""
      parts << "Please provide:"
      parts << "1. A concise PR title (max 72 chars, start with 'fix:')"
      parts << "2. Root cause explanation (2-3 sentences)"
      parts << "3. The code fix (show before/after if applicable)"
      parts << "4. Prevention tips"
      parts << ""
      parts << "Format your response as:"
      parts << "TITLE: <pr title>"
      parts << "ROOT_CAUSE: <explanation>"
      parts << "FIX: <code and explanation>"
      parts << "PREVENTION: <tips>"

      parts.join("\n")
    end

    def parse_ai_pr_response(response, issue, sample_event)
      return {} if response.blank?

      result = {}

      # Parse title
      if response =~ /TITLE:\s*(.+?)(?=ROOT_CAUSE:|FIX:|PREVENTION:|$)/mi
        result[:title] = $1.strip.gsub(/^["']|["']$/, "")
      end

      # Parse sections for body
      root_cause = response =~ /ROOT_CAUSE:\s*(.+?)(?=FIX:|PREVENTION:|$)/mi ? $1.strip : nil
      fix = response =~ /FIX:\s*(.+?)(?=PREVENTION:|$)/mi ? $1.strip : nil
      prevention = response =~ /PREVENTION:\s*(.+?)$/mi ? $1.strip : nil

      # Extract code from fix section
      if fix =~ /```(?:ruby|rb)?\s*(.*?)```/m
        result[:code_fix] = $1.strip
      end

      # Build the body
      parsed = { root_cause: root_cause, fix: fix, fix_code: result[:code_fix], prevention: prevention }
      result[:body] = build_enhanced_pr_body(issue, sample_event, parsed)

      result
    end

    def claude_chat_completion(prompt)
      require "net/http"
      require "json"

      uri = URI.parse("https://api.anthropic.com/v1/messages")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      body = {
        model: "claude-opus-4-20250514",
        max_tokens: 2000,
        system: "You are a senior Rails developer helping fix bugs. Be concise and practical.",
        messages: [
          { role: "user", content: prompt }
        ]
      }

      req = Net::HTTP::Post.new(uri.request_uri)
      req["x-api-key"] = @anthropic_key
      req["anthropic-version"] = "2023-06-01"
      req["Content-Type"] = "application/json"
      req.body = JSON.dump(body)

      res = http.request(req)
      raise "Claude error: #{res.code}" unless res.code.to_i.between?(200, 299)

      json = JSON.parse(res.body)
      json.dig("content", 0, "text")
    end

    def validate_method_structure(code)
      return false if code.blank?

      # Should have "def" and "end"
      has_def = code =~ /^\s*def\s/
      has_end = code =~ /^\s*end\s*$/

      # Count def/end balance
      def_count = code.scan(/\bdef\s/).size
      end_count = code.scan(/\bend\b/).size

      has_def && has_end && def_count <= end_count
    end
  end
end
