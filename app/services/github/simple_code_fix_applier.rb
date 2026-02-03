# frozen_string_literal: true

module Github
  # Simple, reliable code fix applier using line-based replacement
  # Replaces the complex heuristic-based approach with a straightforward diff-like system
  class SimpleCodeFixApplier
    def initialize(api_client:, anthropic_key: nil, source_branch: nil)
      @api_client = api_client
      @anthropic_key = anthropic_key || ENV["ANTHROPIC_API_KEY"]
      @source_branch = source_branch
    end

    def try_apply_actual_fix(owner, repo, sample_event, issue, existing_fix_code = nil, before_code = nil)
      # Get the error frame with source context
      frames = sample_event.structured_stack_trace || []
      error_frame = frames.find { |f| (f["in_app"] || f[:in_app]) && (f["source_context"] || f[:source_context]) }
      return { success: false, reason: "No in-app frame with source context" } unless error_frame

      file_path = error_frame["file"] || error_frame[:file]
      line_number = error_frame["line"] || error_frame[:line]
      source_ctx = error_frame["source_context"] || error_frame[:source_context]

      return { success: false, reason: "Missing file path or line number" } unless file_path && line_number

      # Normalize file path
      normalized_path = normalize_file_path(file_path)
      return { success: false, reason: "Could not normalize path: #{file_path}" } unless normalized_path

      # Fetch current file content from GitHub
      file_url = "/repos/#{owner}/#{repo}/contents/#{normalized_path}"
      file_url += "?ref=#{@source_branch}" if @source_branch.present?
      Rails.logger.info "[SimpleFixApplier] Fetching file: #{file_url}"

      file_response = @api_client.get(file_url)
      return { success: false, reason: "File not found: #{normalized_path}" } unless file_response.is_a?(Hash) && file_response["content"]

      current_content = Base64.decode64(file_response["content"])
      current_lines = current_content.lines

      # Generate a precise fix using AI
      fix_instructions = generate_precise_fix(issue, sample_event, error_frame, current_content, existing_fix_code, before_code)
      return { success: false, reason: "Could not generate fix instructions" } unless fix_instructions

      Rails.logger.info "[SimpleFixApplier] Fix instructions: #{fix_instructions.inspect}"

      # Handle case where fix is needed in a different file
      if fix_instructions[:wrong_file]
        correct_file = fix_instructions[:correct_file]
        if correct_file.present?
          Rails.logger.info "[SimpleFixApplier] Redirecting to correct file: #{correct_file}"
          return apply_fix_to_different_file(owner, repo, correct_file, issue, existing_fix_code)
        else
          return { success: false, reason: "Fix requires different file but path not specified" }
        end
      end

      # Apply the fix
      new_content = apply_line_replacements(current_lines, fix_instructions)
      return { success: false, reason: "Could not apply fix" } unless new_content

      if new_content == current_content
        return { success: false, reason: "Fix produced no changes" }
      end

      # Validate the result (for Ruby files)
      if normalized_path.end_with?(".rb") && !valid_ruby_syntax?(new_content)
        Rails.logger.error "[SimpleFixApplier] Generated invalid Ruby syntax"
        return { success: false, reason: "Generated invalid Ruby syntax" }
      end

      # Create blob with new content
      blob = @api_client.post("/repos/#{owner}/#{repo}/git/blobs", {
        content: new_content,
        encoding: "utf-8"
      })
      blob_sha = blob.is_a?(Hash) ? blob["sha"] : nil
      return { success: false, reason: "Failed to create blob" } unless blob_sha

      {
        success: true,
        tree_entry: { path: normalized_path, mode: "100644", type: "blob", sha: blob_sha },
        file_path: normalized_path
      }
    rescue => e
      Rails.logger.error "[SimpleFixApplier] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      { success: false, reason: e.message }
    end

    private

    def normalize_file_path(path)
      return nil if path.blank?
      path = path.sub(%r{^\./}, "")
      path = path.sub(%r{^.*/app/}, "app/")
      path = path.sub(%r{^.*/lib/}, "lib/")
      path = path.sub(%r{^.*/config/}, "config/")
      if path.start_with?("/")
        match = path.match(%r{/(app|lib|config|spec|test)/.*$})
        path = match[0].sub(%r{^/}, "") if match
      end
      path.presence
    end

    # Generate precise fix instructions using AI
    # Returns: { replacements: [{ line: N, old: "...", new: "..." }, ...] }
    def generate_precise_fix(issue, sample_event, error_frame, file_content, existing_fix_code, before_code = nil)
      return nil unless @anthropic_key.present?

      source_ctx = error_frame["source_context"] || error_frame[:source_context]
      line_number = error_frame["line"] || error_frame[:line]
      method_name = error_frame["method"] || error_frame[:method]
      file_path = error_frame["file"] || error_frame[:file]

      # Build context around error
      lines = file_content.lines
      start_line = [line_number - 10, 1].max
      end_line = [line_number + 10, lines.size].min
      context_lines = lines[(start_line - 1)..(end_line - 1)] || []

      context_with_numbers = context_lines.map.with_index do |line, idx|
        actual_line_num = start_line + idx
        marker = actual_line_num == line_number ? " >>> " : "     "
        "#{actual_line_num.to_s.rjust(4)}#{marker}#{line}"
      end.join

      Rails.logger.info "[SimpleFixApplier] Generating fix for #{file_path}:#{line_number}"
      Rails.logger.info "[SimpleFixApplier] Error: #{issue.exception_class}: #{issue.sample_message&.first(100)}"
      Rails.logger.info "[SimpleFixApplier] Existing fix_code: #{existing_fix_code&.first(100)}"
      Rails.logger.info "[SimpleFixApplier] Before code: #{before_code&.first(100)}" if before_code.present?

      # Build before/after section for clearer context
      before_after_section = if before_code.present? && existing_fix_code.present?
        <<~SECTION
          BEFORE (incorrect code):
          ```
          #{before_code}
          ```

          AFTER (corrected code):
          ```
          #{existing_fix_code}
          ```
        SECTION
      elsif existing_fix_code.present?
        <<~SECTION
          CORRECTED CODE (replace the error line with this):
          ```
          #{existing_fix_code}
          ```
        SECTION
      else
        ""
      end

      prompt = <<~PROMPT
        Fix this error by providing EXACT line replacements. Be minimal - only change what's necessary.

        ERROR: #{issue.exception_class}
        MESSAGE: #{issue.sample_message}
        FILE: #{file_path}
        ERROR LINE: #{line_number}

        CODE CONTEXT (line #{start_line}-#{end_line}, error on line #{line_number} marked with >>>):
        ```
        #{context_with_numbers}
        ```

        #{before_after_section}

        ANALYSIS STEPS:
        1. Look at the ERROR LINE (marked with >>>)
        2. Look at the CORRECTED CODE above - this shows what it SHOULD be
        3. Compare them to understand the fix (e.g., typo "rot" -> "root")
        4. Create a replacement with the EXACT old line from context and the corrected new line

        SPECIAL CASES:
        - If the fix requires a DIFFERENT file, return: {"wrong_file": true, "correct_file": "path/to/file.rb"}
        - For simple typos, just replace the error line

        RESPOND WITH ONLY A JSON OBJECT in this exact format:
        {
          "replacements": [
            {"line": LINE_NUMBER, "old": "EXACT old line content", "new": "new line content"}
          ],
          "insertions": [
            {"after_line": LINE_NUMBER, "content": "new code to insert\\ncan be multiple lines"}
          ]
        }

        RULES:
        1. Use "replacements" to CHANGE existing lines (old != new)
        2. Use "insertions" to ADD new code (e.g., new methods, new lines)
        3. "old" must be the EXACT current line content (copy-paste from context)
        4. "new" must be DIFFERENT from "old" - if they're the same, use "insertions" instead
        5. Preserve ALL indentation exactly (spaces/tabs)
        6. Line numbers must match the context above
        7. Do NOT include line numbers or markers in values
        8. For "insertions", use \\n for newlines within content
        9. Return ONLY valid JSON, no markdown, no explanation

        JSON:
      PROMPT

      response = claude_completion(prompt)
      Rails.logger.info "[SimpleFixApplier] Claude response: #{response&.first(500)}"
      return nil if response.blank?

      # Parse JSON response
      json_match = response.match(/\{[\s\S]*\}/)
      unless json_match
        Rails.logger.error "[SimpleFixApplier] No JSON found in Claude response"
        return nil
      end
      Rails.logger.info "[SimpleFixApplier] Extracted JSON: #{json_match[0].first(300)}"

      begin
        parsed = JSON.parse(json_match[0])

        # Check if fix requires a different file
        if parsed["wrong_file"] == true
          correct_file = parsed["correct_file"]
          Rails.logger.info "[SimpleFixApplier] Fix requires different file: #{correct_file}"
          return { wrong_file: true, correct_file: correct_file }
        end

        result = {}

        # Validate replacements (must have different old/new)
        if parsed["replacements"].is_a?(Array)
          valid_replacements = parsed["replacements"].select do |r|
            r["line"].is_a?(Integer) &&
              r["old"].is_a?(String) &&
              r["new"].is_a?(String) &&
              r["old"].strip != r["new"].strip # Must be different!
          end
          result[:replacements] = valid_replacements if valid_replacements.any?
        end

        # Validate insertions
        if parsed["insertions"].is_a?(Array)
          valid_insertions = parsed["insertions"].select do |i|
            i["after_line"].is_a?(Integer) && i["content"].is_a?(String) && i["content"].present?
          end
          result[:insertions] = valid_insertions if valid_insertions.any?
        end

        if result.empty?
          Rails.logger.error "[SimpleFixApplier] No valid replacements or insertions found in parsed JSON"
          Rails.logger.error "[SimpleFixApplier] Parsed data: #{parsed.inspect}"
          return nil
        end

        result
      rescue JSON::ParserError => e
        Rails.logger.error "[SimpleFixApplier] JSON parse error: #{e.message}"
        Rails.logger.error "[SimpleFixApplier] Raw JSON: #{json_match[0].first(500)}"
        nil
      end
    end

    # Apply line-by-line replacements and insertions
    def apply_line_replacements(lines, fix_instructions)
      return nil if fix_instructions.nil? || (fix_instructions[:replacements].blank? && fix_instructions[:insertions].blank?)

      new_lines = lines.dup
      changes_made = 0

      # First, apply insertions (in reverse order to maintain line numbers)
      if fix_instructions[:insertions].present?
        fix_instructions[:insertions].sort_by { |i| -i["after_line"] }.each do |insertion|
          after_idx = insertion["after_line"] # 1-indexed, insert after this line
          content = insertion["content"]

          next if after_idx < 0 || after_idx > new_lines.size

          # Determine indentation from the reference line
          ref_line = after_idx > 0 ? new_lines[after_idx - 1] : new_lines[0]
          base_indent = ref_line&.match(/^(\s*)/)[1] || ""

          # Split content by newlines and add proper indentation
          insertion_lines = content.split("\\n").map do |line|
            line_content = line.strip
            if line_content.empty?
              "\n"
            else
              # Detect if line has its own indentation hint (starts with spaces)
              if line.match?(/^\s+/)
                # Use relative indentation from content
                "#{line.rstrip}\n"
              else
                "#{base_indent}#{line_content}\n"
              end
            end
          end

          # Insert after the specified line
          new_lines.insert(after_idx, *insertion_lines)
          changes_made += 1
          Rails.logger.info "[SimpleFixApplier] Inserted #{insertion_lines.size} lines after line #{after_idx}"
        end
      end

      # Then, apply replacements
      (fix_instructions[:replacements] || []).sort_by { |r| -r["line"] }.each do |replacement|
        line_idx = replacement["line"] - 1
        old_content = replacement["old"]
        new_content = replacement["new"]

        next if line_idx < 0 || line_idx >= new_lines.size

        current_line = new_lines[line_idx]

        # Try exact match first
        if current_line.chomp == old_content.chomp || current_line.strip == old_content.strip
          # Preserve original line ending
          line_ending = current_line.end_with?("\n") ? "\n" : ""

          # Preserve original indentation if new content doesn't have it
          original_indent = current_line.match(/^(\s*)/)[1]
          new_stripped = new_content.strip

          if new_content.match(/^(\s*)/)[1].empty? && original_indent.present?
            new_lines[line_idx] = "#{original_indent}#{new_stripped}#{line_ending}"
          else
            new_lines[line_idx] = "#{new_content.chomp}#{line_ending}"
          end

          changes_made += 1
          Rails.logger.info "[SimpleFixApplier] Replaced line #{replacement['line']}: #{old_content.strip[0..50]} -> #{new_stripped[0..50]}"
        else
          Rails.logger.warn "[SimpleFixApplier] Line #{replacement['line']} mismatch:"
          Rails.logger.warn "  Expected: #{old_content.inspect}"
          Rails.logger.warn "  Actual:   #{current_line.inspect}"

          # Try fuzzy match - same line content ignoring whitespace differences
          if current_line.gsub(/\s+/, " ").strip == old_content.gsub(/\s+/, " ").strip
            original_indent = current_line.match(/^(\s*)/)[1]
            new_stripped = new_content.strip
            line_ending = current_line.end_with?("\n") ? "\n" : ""
            new_lines[line_idx] = "#{original_indent}#{new_stripped}#{line_ending}"
            changes_made += 1
            Rails.logger.info "[SimpleFixApplier] Fuzzy match succeeded for line #{replacement['line']}"
          end
        end
      end

      return nil if changes_made == 0

      new_lines.join
    end

    # Apply fix to a different file than where the error occurred
    def apply_fix_to_different_file(owner, repo, file_path, issue, existing_fix_code)
      normalized_path = normalize_file_path(file_path)
      return { success: false, reason: "Could not normalize path: #{file_path}" } unless normalized_path

      # Fetch the target file
      file_url = "/repos/#{owner}/#{repo}/contents/#{normalized_path}"
      file_url += "?ref=#{@source_branch}" if @source_branch.present?
      Rails.logger.info "[SimpleFixApplier] Fetching alternate file: #{file_url}"

      file_response = @api_client.get(file_url)
      return { success: false, reason: "Alternate file not found: #{normalized_path}" } unless file_response.is_a?(Hash) && file_response["content"]

      current_content = Base64.decode64(file_response["content"])
      current_lines = current_content.lines

      # Generate fix for this file
      fix_instructions = generate_fix_for_file(normalized_path, current_content, issue, existing_fix_code)
      return { success: false, reason: "Could not generate fix for alternate file" } unless fix_instructions

      Rails.logger.info "[SimpleFixApplier] Fix instructions for alternate file: #{fix_instructions.inspect}"

      # Apply the fix
      new_content = apply_line_replacements(current_lines, fix_instructions)
      return { success: false, reason: "Could not apply fix to alternate file" } unless new_content

      if new_content == current_content
        return { success: false, reason: "Fix produced no changes in alternate file" }
      end

      # Validate the result
      if normalized_path.end_with?(".rb") && !valid_ruby_syntax?(new_content)
        Rails.logger.error "[SimpleFixApplier] Generated invalid Ruby syntax for alternate file"
        return { success: false, reason: "Generated invalid Ruby syntax" }
      end

      # Create blob
      blob = @api_client.post("/repos/#{owner}/#{repo}/git/blobs", {
        content: new_content,
        encoding: "utf-8"
      })
      blob_sha = blob.is_a?(Hash) ? blob["sha"] : nil
      return { success: false, reason: "Failed to create blob for alternate file" } unless blob_sha

      {
        success: true,
        tree_entry: { path: normalized_path, mode: "100644", type: "blob", sha: blob_sha },
        file_path: normalized_path
      }
    end

    # Generate fix for a file that's different from the error location
    def generate_fix_for_file(file_path, file_content, issue, existing_fix_code)
      return nil unless @anthropic_key.present?

      lines = file_content.lines
      # Show first 50 lines for context (usually enough for a model file)
      context_lines = lines.first(50)
      context_with_numbers = context_lines.map.with_index do |line, idx|
        "#{(idx + 1).to_s.rjust(4)}     #{line}"
      end.join

      prompt = <<~PROMPT
        Add the required code to fix this error. The fix needs to be added to THIS file.

        ERROR: #{issue.exception_class}
        MESSAGE: #{issue.sample_message}

        FILE TO MODIFY: #{file_path}
        CURRENT CONTENT (first 50 lines):
        ```
        #{context_with_numbers}
        ```

        SUGGESTED FIX:
        ```
        #{existing_fix_code}
        ```

        RESPOND WITH ONLY A JSON OBJECT:
        {
          "insertions": [
            {"after_line": LINE_NUMBER, "content": "code to insert\\nwith proper indentation"}
          ]
        }

        RULES:
        1. Find the right place to insert the new code (usually before the last "end" of a class/module)
        2. Use proper indentation (2 spaces per level for Ruby)
        3. For "insertions", use \\n for newlines within content
        4. Return ONLY valid JSON, no markdown

        JSON:
      PROMPT

      response = claude_completion(prompt)
      return nil if response.blank?

      json_match = response.match(/\{[\s\S]*\}/)
      return nil unless json_match

      begin
        parsed = JSON.parse(json_match[0])
        result = {}

        if parsed["insertions"].is_a?(Array)
          valid_insertions = parsed["insertions"].select do |i|
            i["after_line"].is_a?(Integer) && i["content"].is_a?(String) && i["content"].present?
          end
          result[:insertions] = valid_insertions if valid_insertions.any?
        end

        return nil if result.empty?
        result
      rescue JSON::ParserError => e
        Rails.logger.error "[SimpleFixApplier] JSON parse error for alternate file: #{e.message}"
        nil
      end
    end

    def valid_ruby_syntax?(content)
      RubyVM::InstructionSequence.compile(content)
      true
    rescue SyntaxError
      false
    rescue => e
      # Other errors (missing constants etc) are OK
      true
    end

    def claude_completion(prompt)
      require "net/http"
      require "json"

      uri = URI.parse("https://api.anthropic.com/v1/messages")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 30

      body = {
        model: "claude-sonnet-4-20250514",
        max_tokens: 1500,
        messages: [{ role: "user", content: prompt }]
      }

      req = Net::HTTP::Post.new(uri.request_uri)
      req["x-api-key"] = @anthropic_key
      req["anthropic-version"] = "2023-06-01"
      req["Content-Type"] = "application/json"
      req.body = JSON.dump(body)

      res = http.request(req)
      unless res.code.to_i.between?(200, 299)
        Rails.logger.error "[SimpleFixApplier] Claude API error: #{res.code} - #{res.body.first(200)}"
        return nil
      end

      json = JSON.parse(res.body)
      json.dig("content", 0, "text")
    end
  end
end
