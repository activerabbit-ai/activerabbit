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
      @owner = owner
      @repo = repo

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

      # Fetch related files for better context
      related_files_context = fetch_related_files_context(normalized_path, current_content, frames, issue)
      Rails.logger.info "[SimpleFixApplier] Fetched #{related_files_context[:files_fetched]} related files for context"

      # Generate a precise fix using AI with extended context
      fix_instructions = generate_precise_fix(issue, sample_event, error_frame, current_content, existing_fix_code, before_code, related_files_context)
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

    # Apply a fix to a specific file (for multi-file fixes)
    # Uses before/after code to find and replace content
    def try_apply_fix_to_file(owner, repo, file_path, before_code, after_code)
      @owner = owner
      @repo = repo

      return { success: false, reason: "Missing file path" } if file_path.blank?
      return { success: false, reason: "Missing fix code" } if after_code.blank?

      # Normalize file path
      normalized_path = normalize_file_path(file_path)
      return { success: false, reason: "Could not normalize path: #{file_path}" } unless normalized_path

      # Fetch current file content from GitHub
      file_url = "/repos/#{owner}/#{repo}/contents/#{normalized_path}"
      file_url += "?ref=#{@source_branch}" if @source_branch.present?
      Rails.logger.info "[SimpleFixApplier] Fetching additional file: #{file_url}"

      file_response = @api_client.get(file_url)
      return { success: false, reason: "File not found: #{normalized_path}" } unless file_response.is_a?(Hash) && file_response["content"]

      current_content = Base64.decode64(file_response["content"])
      new_content = nil

      # Try direct replacement if before_code is provided
      if before_code.present?
        direct_result = try_direct_replacement(current_content, before_code, after_code, 1)
        if direct_result && direct_result[:replacements].present?
          Rails.logger.info "[SimpleFixApplier] Direct replacement succeeded for #{normalized_path}"

          # Apply the replacements
          lines = current_content.lines
          direct_result[:replacements].sort_by { |r| -r[:line] }.each do |replacement|
            line_idx = replacement[:line] - 1
            next if line_idx < 0 || line_idx >= lines.size

            original_indent = lines[line_idx].match(/^(\s*)/)[1]
            line_ending = lines[line_idx].end_with?("\n") ? "\n" : ""
            new_stripped = replacement[:new].strip
            lines[line_idx] = "#{original_indent}#{new_stripped}#{line_ending}"
          end
          new_content = lines.join
        end
      end

      # If direct replacement fails, try simple string replacement
      if new_content.nil? && before_code.present?
        if current_content.include?(before_code.strip)
          new_content = current_content.sub(before_code.strip, after_code.strip)
          Rails.logger.info "[SimpleFixApplier] Simple string replacement succeeded for #{normalized_path}"
        end
      end

      # If still no match, try to add new code (for adding new methods)
      if new_content.nil? && after_code.present? && before_code.blank?
        # Append before the last 'end' (usually class/module end)
        lines = current_content.lines
        last_end_idx = lines.rindex { |l| l.strip == "end" }

        if last_end_idx && last_end_idx > 0
          indent = lines[last_end_idx - 1].match(/^(\s*)/)[1] rescue "  "
          indented_code = after_code.lines.map { |l| l.strip.empty? ? "\n" : "#{indent}#{l.rstrip}\n" }.join

          lines.insert(last_end_idx, "\n#{indented_code}")
          new_content = lines.join
          Rails.logger.info "[SimpleFixApplier] Inserted new code into #{normalized_path}"
        end
      end

      return { success: false, reason: "Could not apply fix to #{normalized_path}" } unless new_content

      # Create blob
      blob = @api_client.post("/repos/#{owner}/#{repo}/git/blobs", {
        content: new_content,
        encoding: "utf-8"
      })
      blob_sha = blob.is_a?(Hash) ? blob["sha"] : nil
      return { success: false, reason: "Failed to create blob for #{normalized_path}" } unless blob_sha

      {
        success: true,
        tree_entry: { path: normalized_path, mode: "100644", type: "blob", sha: blob_sha },
        file_path: normalized_path
      }
    rescue => e
      Rails.logger.error "[SimpleFixApplier] Error applying fix to #{file_path}: #{e.message}"
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

    # Fetch related files to provide better context for the AI
    # Returns: { context: "...", files_fetched: N }
    def fetch_related_files_context(error_file_path, error_file_content, stack_frames, issue)
      related_files = []
      files_to_fetch = []

      # 1. Extract model/class names referenced in the error file
      referenced_classes = extract_referenced_classes(error_file_content)
      Rails.logger.info "[SimpleFixApplier] Referenced classes: #{referenced_classes.join(', ')}"

      # 2. Determine related files based on error file type
      if error_file_path.include?("/controllers/")
        # For controllers, fetch related model and possibly the view
        controller_name = File.basename(error_file_path, ".rb").sub(/_controller$/, "")
        model_name = controller_name.singularize
        files_to_fetch << "app/models/#{model_name}.rb"

        # Also check for service objects
        referenced_classes.each do |klass|
          if klass.end_with?("Service")
            files_to_fetch << "app/services/#{klass.underscore}.rb"
          end
        end

      elsif error_file_path.include?("/models/")
        # For models, fetch related models (associations)
        referenced_classes.each do |klass|
          files_to_fetch << "app/models/#{klass.underscore}.rb"
        end

      elsif error_file_path.include?("/services/")
        # For services, fetch models they use
        referenced_classes.each do |klass|
          if !klass.end_with?("Service")
            files_to_fetch << "app/models/#{klass.underscore}.rb"
          end
        end

      elsif error_file_path.include?("/jobs/")
        # For jobs, fetch related models and services
        referenced_classes.each do |klass|
          if klass.end_with?("Service")
            files_to_fetch << "app/services/#{klass.underscore}.rb"
          else
            files_to_fetch << "app/models/#{klass.underscore}.rb"
          end
        end
      end

      # 3. Add files from stack trace (in-app frames only)
      stack_frames.select { |f| f["in_app"] || f[:in_app] }.first(5).each do |frame|
        frame_file = frame["file"] || frame[:file]
        next if frame_file.blank?
        normalized = normalize_file_path(frame_file)
        files_to_fetch << normalized if normalized && normalized != error_file_path
      end

      # 4. Check for schema.rb if dealing with database/model errors
      if issue.exception_class.to_s.include?("ActiveRecord") ||
         issue.sample_message.to_s.include?("column") ||
         issue.sample_message.to_s.include?("table")
        files_to_fetch << "db/schema.rb"
      end

      # Dedupe and limit
      files_to_fetch = files_to_fetch.uniq.reject { |f| f == error_file_path }.first(5)

      # Fetch each file
      files_to_fetch.each do |file_path|
        content = fetch_file_content(file_path)
        if content
          # Truncate large files to first 100 lines
          truncated = content.lines.first(100).join
          if content.lines.size > 100
            truncated += "\n# ... (truncated, #{content.lines.size - 100} more lines)"
          end
          related_files << { path: file_path, content: truncated }
          Rails.logger.info "[SimpleFixApplier] Fetched related file: #{file_path} (#{content.lines.size} lines)"
        end
      end

      # Build context string
      context_parts = []
      related_files.each do |file|
        context_parts << <<~FILE
          === #{file[:path]} ===
          ```ruby
          #{file[:content]}
          ```
        FILE
      end

      {
        context: context_parts.join("\n"),
        files_fetched: related_files.size,
        files: related_files
      }
    end

    # Extract class names referenced in Ruby code
    def extract_referenced_classes(content)
      classes = []

      # Match class references like User, Product, OrderService, etc.
      # Look for: ClassName.method, ClassName::Constant, belongs_to :class_name, has_many :class_names
      content.scan(/\b([A-Z][a-zA-Z0-9]+)(?:\.|::|\s)/).each do |match|
        classes << match[0]
      end

      # Match association declarations
      content.scan(/(?:belongs_to|has_one|has_many|has_and_belongs_to_many)\s+:(\w+)/).each do |match|
        classes << match[0].classify
      end

      # Match common Rails patterns
      content.scan(/(\w+)\.(?:find|find_by|where|create|new|first|last|all)/).each do |match|
        word = match[0]
        classes << word if word.match?(/^[A-Z]/)
      end

      # Filter out common non-model classes
      excluded = %w[Rails ActiveRecord ActionController ApplicationController ApplicationRecord
                    String Integer Float Array Hash Time DateTime Date File Logger JSON
                    Thread Mutex Queue ENV Kernel Object Class Module]

      classes.uniq.reject { |c| excluded.include?(c) || c.length < 3 }
    end

    # Fetch a single file from GitHub
    def fetch_file_content(file_path)
      return nil if file_path.blank?

      file_url = "/repos/#{@owner}/#{@repo}/contents/#{file_path}"
      file_url += "?ref=#{@source_branch}" if @source_branch.present?

      response = @api_client.get(file_url)
      return nil unless response.is_a?(Hash) && response["content"]

      Base64.decode64(response["content"])
    rescue => e
      Rails.logger.debug "[SimpleFixApplier] Could not fetch #{file_path}: #{e.message}"
      nil
    end

    # Try to apply fix directly without AI by matching before_code in the file
    # Returns fix instructions if successful, nil if matching fails
    def try_direct_replacement(file_content, before_code, after_code, error_line)
      return nil if before_code.blank? || after_code.blank?

      lines = file_content.lines
      before_lines = before_code.strip.lines.map(&:rstrip)
      after_lines = after_code.strip.lines

      # Try to find the before_code block in the file
      # Start searching near the error line
      search_start = [error_line - 20, 0].max
      search_end = [error_line + 20, lines.size - 1].min

      match_start = nil
      (search_start..search_end).each do |i|
        # Check if before_lines match starting at line i
        matches = true
        before_lines.each_with_index do |before_line, j|
          file_line = lines[i + j]&.rstrip || ""
          # Normalize whitespace for comparison
          if normalize_code(file_line) != normalize_code(before_line)
            matches = false
            break
          end
        end

        if matches
          match_start = i
          break
        end
      end

      return nil unless match_start

      Rails.logger.info "[SimpleFixApplier] Direct match found at line #{match_start + 1}"

      # Build replacement instructions
      replacements = []
      before_lines.each_with_index do |old_line, idx|
        line_num = match_start + idx + 1
        new_line = after_lines[idx] || ""

        # Preserve original indentation from file
        original_indent = lines[match_start + idx]&.match(/^(\s*)/)&.[](1) || ""
        new_content = original_indent + new_line.lstrip
        old_content = lines[match_start + idx]&.chomp || old_line

        # Only include replacement if old != new (skip unchanged lines)
        next if old_content.strip == new_content.strip

        replacements << {
          line: line_num,
          old: old_content,
          new: new_content.chomp
        }
      end

      # Handle case where after_code has more lines (insertion)
      if after_lines.size > before_lines.size
        insertions = []
        after_lines[before_lines.size..].each_with_index do |new_line, idx|
          insert_after = match_start + before_lines.size + idx
          original_indent = lines[match_start]&.match(/^(\s*)/)&.[](1) || ""
          insertions << {
            after_line: insert_after,
            content: original_indent + new_line.lstrip.chomp
          }
        end
        return { replacements: replacements, insertions: insertions } if insertions.any?
      end

      return nil if replacements.empty?

      { replacements: replacements }
    rescue => e
      Rails.logger.warn "[SimpleFixApplier] Direct replacement failed: #{e.message}"
      nil
    end

    # Normalize code for comparison (strip whitespace, downcase)
    def normalize_code(line)
      line.to_s.strip.gsub(/\s+/, " ")
    end

    # Generate precise fix instructions using AI
    # Returns: { replacements: [{ line: N, old: "...", new: "..." }, ...] }
    def generate_precise_fix(issue, sample_event, error_frame, file_content, existing_fix_code, before_code = nil, related_files_context = nil)
      source_ctx = error_frame["source_context"] || error_frame[:source_context]
      line_number = error_frame["line"] || error_frame[:line]
      method_name = error_frame["method"] || error_frame[:method]
      file_path = error_frame["file"] || error_frame[:file]

      # FAST PATH: If we have before_code and after_code, try direct replacement without AI
      if before_code.present? && existing_fix_code.present?
        direct_result = try_direct_replacement(file_content, before_code, existing_fix_code, line_number)
        if direct_result
          Rails.logger.info "[SimpleFixApplier] FAST PATH: Applied fix directly without AI call"
          return direct_result
        end
        Rails.logger.info "[SimpleFixApplier] FAST PATH failed, falling back to AI"
      end

      return nil unless @anthropic_key.present?

      # Build context around error - expand to 30 lines for better understanding
      lines = file_content.lines
      start_line = [line_number - 20, 1].max
      end_line = [line_number + 15, lines.size].min
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
          SUGGESTED FIX FROM AI ANALYSIS:

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
          SUGGESTED FIX FROM AI ANALYSIS:
          ```
          #{existing_fix_code}
          ```
        SECTION
      else
        ""
      end

      # Build related files section
      related_files_section = ""
      if related_files_context && related_files_context[:context].present?
        related_files_section = <<~SECTION

          RELATED FILES (for understanding the codebase context):
          #{related_files_context[:context]}
        SECTION
      end

      prompt = <<~PROMPT
        You are fixing a bug in a Ruby on Rails application. Analyze the error, the code context, and related files to provide an accurate fix.

        ERROR: #{issue.exception_class}
        MESSAGE: #{issue.sample_message}
        FILE: #{file_path}
        ERROR LINE: #{line_number}

        ERROR FILE CONTEXT (line #{start_line}-#{end_line}, error on line #{line_number} marked with >>>):
        ```ruby
        #{context_with_numbers}
        ```

        #{before_after_section}
        #{related_files_section}

        TASK: Provide EXACT line replacements to fix this error. Be precise and minimal.

        ANALYSIS CHECKLIST:
        1. Understand the error type and message
        2. Look at the ERROR LINE (marked with >>>)
        3. Check related files for context (models, associations, validations)
        4. If a suggested fix is provided, apply it to the correct line
        5. Ensure the fix matches the codebase patterns

        SPECIAL CASES:
        - If the fix requires a DIFFERENT file, return: {"wrong_file": true, "correct_file": "path/to/file.rb"}
        - For missing methods/associations, you may need to add code

        RESPOND WITH ONLY A JSON OBJECT:
        {
          "replacements": [
            {"line": LINE_NUMBER, "old": "EXACT old line content", "new": "new line content"}
          ],
          "insertions": [
            {"after_line": LINE_NUMBER, "content": "new code to insert\\nwith proper indentation"}
          ]
        }

        CRITICAL RULES:
        1. "old" must EXACTLY match the current line content (copy from context above)
        2. "new" must be DIFFERENT from "old"
        3. Preserve ALL indentation (spaces/tabs)
        4. Line numbers must match the context above
        5. Use \\n for newlines in insertions
        6. Return ONLY valid JSON, no markdown

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
        fix_instructions[:insertions].sort_by { |i| -(i[:after_line] || i["after_line"]) }.each do |insertion|
          after_idx = insertion[:after_line] || insertion["after_line"] # 1-indexed, insert after this line
          content = insertion[:content] || insertion["content"]

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
      (fix_instructions[:replacements] || []).sort_by { |r| -(r[:line] || r["line"]) }.each do |replacement|
        line_num = replacement[:line] || replacement["line"]
        line_idx = line_num - 1
        old_content = replacement[:old] || replacement["old"]
        new_content = replacement[:new] || replacement["new"]

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
          Rails.logger.info "[SimpleFixApplier] Replaced line #{line_num}: #{old_content.strip[0..50]} -> #{new_stripped[0..50]}"
        else
          Rails.logger.warn "[SimpleFixApplier] Line #{line_num} mismatch:"
          Rails.logger.warn "  Expected: #{old_content.inspect}"
          Rails.logger.warn "  Actual:   #{current_line.inspect}"

          # Try fuzzy match - same line content ignoring whitespace differences
          if current_line.gsub(/\s+/, " ").strip == old_content.gsub(/\s+/, " ").strip
            original_indent = current_line.match(/^(\s*)/)[1]
            new_stripped = new_content.strip
            line_ending = current_line.end_with?("\n") ? "\n" : ""
            new_lines[line_idx] = "#{original_indent}#{new_stripped}#{line_ending}"
            changes_made += 1
            Rails.logger.info "[SimpleFixApplier] Fuzzy match succeeded for line #{line_num}"
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
        model: "claude-opus-4-20250514",
        max_tokens: 2500,
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
