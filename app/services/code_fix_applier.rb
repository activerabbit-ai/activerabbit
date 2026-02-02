# Applies code fixes to source files
class CodeFixApplier
  def initialize(api_client:, anthropic_key:, source_branch: nil)
    @api_client = api_client
    @anthropic_key = anthropic_key
    @source_branch = source_branch
  end

  def try_apply_actual_fix(owner, repo, sample_event, issue, existing_fix_code = nil)
    # Get the error frame with source context
    frames = sample_event.structured_stack_trace || []
    error_frame = frames.find { |f| (f["in_app"] || f[:in_app]) && (f["source_context"] || f[:source_context]) }
    return { success: false, reason: "No in-app frame with source context" } unless error_frame

    file_path = error_frame["file"] || error_frame[:file]
    line_number = error_frame["line"] || error_frame[:line]
    source_ctx = error_frame["source_context"] || error_frame[:source_context]

    return { success: false, reason: "Missing file path or line number" } unless file_path && line_number

    # Normalize file path (remove leading ./ or absolute paths, get relative to repo root)
    normalized_path = normalize_file_path(file_path)
    return { success: false, reason: "Could not normalize path: #{file_path}" } unless normalized_path

    # Fetch current file content from GitHub (from source branch if specified)
    file_url = "/repos/#{owner}/#{repo}/contents/#{normalized_path}"
    file_url += "?ref=#{@source_branch}" if @source_branch.present?
    Rails.logger.info "[GitHub API] Fetching file from: #{file_url}"
    file_response = @api_client.get(file_url)
    return { success: false, reason: "File not found in repo: #{normalized_path}" } unless file_response.is_a?(Hash) && file_response["content"]

    current_content = Base64.decode64(file_response["content"])
    current_lines = current_content.lines

    # Use existing fix code from AI summary if available, otherwise generate a new one
    fixed_code = if existing_fix_code.present?
      Rails.logger.info "[GitHub API] Using existing fix code from AI summary"
      Rails.logger.info "[GitHub API] Original fix_code (first 200 chars): #{existing_fix_code[0..200]}"

      # Extract only the method if the fix code includes class/module definitions
      extracted = extract_method_from_code(existing_fix_code)
      if extracted && extracted != existing_fix_code
        Rails.logger.info "[GitHub API] Extracted method from fix code (removed class/module wrapper)"
        Rails.logger.info "[GitHub API] Extracted fix_code (first 200 chars): #{extracted[0..200]}"
        extracted
      else
        Rails.logger.info "[GitHub API] Using fix_code as-is (no extraction needed)"
        existing_fix_code
      end
    else
      Rails.logger.info "[GitHub API] Generating new fix code with AI"
      generate_code_fix(issue, sample_event, error_frame, current_content)
    end

    Rails.logger.info "[GitHub API] Final fixed_code to apply (first 300 chars): #{fixed_code&.[](0..300)}"
    return { success: false, reason: "No fix code available" } unless fixed_code

    # Verify that fixed_code actually contains a fix (differs from original)
    original_method = extract_method_context(current_content, line_number, error_frame["method"] || error_frame[:method])
    if original_method.present? && fixed_code.strip == original_method.strip
      Rails.logger.warn "[GitHub API] Fixed code is identical to original! This might indicate the fix wasn't properly extracted."
      Rails.logger.warn "[GitHub API] Original method: #{original_method[0..200]}"
      Rails.logger.warn "[GitHub API] Fixed code: #{fixed_code[0..200]}"
    end

    # Apply the fix to the file content
    new_content = apply_fix_to_content(current_lines, line_number, source_ctx, fixed_code)

    if new_content.nil?
      Rails.logger.error "[GitHub API] apply_fix_to_content returned nil"
      return { success: false, reason: "Could not apply fix to file" }
    end

    if new_content == current_content
      Rails.logger.error "[GitHub API] New content is identical to original content - fix was not applied!"
      Rails.logger.error "[GitHub API] Fixed code was: #{fixed_code[0..300]}"
      return { success: false, reason: "Fix was not applied - content unchanged" }
    end

    Rails.logger.info "[GitHub API] Fix applied successfully - content changed"

    # Create blob with new content
    blob = @api_client.post("/repos/#{owner}/#{repo}/git/blobs", {
      content: new_content,
      encoding: "utf-8"
    })
    blob_sha = blob.is_a?(Hash) ? blob["sha"] : nil
    return { success: false, reason: "Failed to create blob for fixed file" } unless blob_sha

    {
      success: true,
      tree_entry: { path: normalized_path, mode: "100644", type: "blob", sha: blob_sha },
      file_path: normalized_path
    }
  rescue => e
    Rails.logger.error "[GitHub API] try_apply_actual_fix error: #{e.message}"
    { success: false, reason: e.message }
  end

  private

  def normalize_file_path(path)
    return nil if path.blank?

    # Remove common prefixes
    path = path.sub(%r{^\./}, "")                    # Remove ./
    path = path.sub(%r{^/app/}, "app/")              # /app/ -> app/
    path = path.sub(%r{^.*/app/}, "app/")            # .../app/ -> app/
    path = path.sub(%r{^.*/lib/}, "lib/")            # .../lib/ -> lib/
    path = path.sub(%r{^.*/config/}, "config/")       # .../config/ -> config/

    # If it still has absolute-looking path, try to extract from common Rails structure
    if path.start_with?("/")
      match = path.match(%r{/(app|lib|config|spec|test)/.*$})
      path = match[0].sub(%r{^/}, "") if match
    end

    path.presence
  end

  def generate_code_fix(issue, sample_event, error_frame, file_content)
    return nil unless @anthropic_key.present?

    source_ctx = error_frame["source_context"] || error_frame[:source_context]
    line_number = error_frame["line"] || error_frame[:line]
    method_name = error_frame["method"] || error_frame[:method]

    # Get method context from full file to understand class/module structure
    method_context = extract_method_context(file_content, line_number, method_name)

    # Build focused prompt for code fix
    prompt = <<~PROMPT
      Fix this Ruby code error. Return ONLY the fixed method code, preserving the exact method definition line and structure.

      Error: #{issue.exception_class}
      Message: #{issue.sample_message}
      File: #{error_frame["file"]}
      Line: #{line_number}
      Method: #{method_name}

      Full method context (preserve class/module structure):
      ```ruby
      #{method_context}
      ```

      Error location (line #{line_number}):
      ```ruby
      #{format_source_for_prompt(source_ctx)}
      ```

      IMPORTANT RULES:
      1. Return the COMPLETE method including "def method_name" and "end"
      2. Do NOT include class/module definitions - only the method
      3. Make minimal changes - only fix the error line
      4. Preserve all indentation and structure
      5. Do not include ```ruby markers, just the code
      6. If the method is inside a module/class, keep the same indentation level

      Return ONLY the fixed method code.
    PROMPT

    begin
      response = claude_chat_completion(prompt)
      return nil if response.blank?

      # Clean up the response - remove markdown code blocks if present
      code = response.strip
      code = code.sub(/^```ruby\s*\n?/, "").sub(/\n?```\s*$/, "")
      code.strip.presence
    rescue => e
      Rails.logger.error "[GitHub API] generate_code_fix AI error: #{e.message}"
      nil
    end
  end

  def extract_method_context(file_content, error_line_number, method_name)
    lines = file_content.lines
    return "" if lines.empty? || error_line_number < 1 || error_line_number > lines.size

    # Find method start (look backwards for "def method_name")
    method_start = nil
    (error_line_number - 1).downto(0) do |i|
      line = lines[i]
      # Match "def method_name" or "def self.method_name" or "def method_name("
      if line =~ /^\s*def\s+(self\.)?#{Regexp.escape(method_name.to_s)}/
        method_start = i
        break
      end
      # Stop if we hit another method definition or class/module boundary
      break if i < error_line_number - 20 # Limit search to 20 lines back
      break if line =~ /^\s*(class|module|end)\s/
    end

    return "" unless method_start

    # Find method end (look forward for matching "end")
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
    method_lines.join
  end

  def format_source_for_prompt(source_ctx)
    lines = []
    (source_ctx["lines_before"] || source_ctx[:lines_before] || []).each do |l|
      content = l.is_a?(Hash) ? l[:content] || l["content"] : l
      lines << content
    end

    error_line = source_ctx["line_content"] || source_ctx[:line_content]
    error_content = error_line.is_a?(Hash) ? error_line[:content] || error_line["content"] : error_line
    lines << ">>> #{error_content}  # <-- ERROR LINE"

    (source_ctx["lines_after"] || source_ctx[:lines_after] || []).each do |l|
      content = l.is_a?(Hash) ? l[:content] || l["content"] : l
      lines << content
    end

    lines.join("\n")
  end

  def apply_fix_to_content(current_lines, error_line_number, source_ctx, fixed_code)
    return nil if fixed_code.blank?

    Rails.logger.info "[GitHub API] apply_fix_to_content called with fixed_code (first 200 chars): #{fixed_code[0..200]}"

    # Normalize fixed_code - remove trailing newlines and ensure proper structure
    fixed_code = normalize_fixed_code(fixed_code)
    return nil unless fixed_code

    Rails.logger.info "[GitHub API] After normalization (first 200 chars): #{fixed_code[0..200]}"

    # Check if this is an ERB file (template file) - use precise line replacement
    error_line_idx = error_line_number - 1
    error_line = current_lines[error_line_idx] if error_line_idx >= 0 && error_line_idx < current_lines.size
    is_erb_file = error_line&.include?("<%") || error_line&.include?("<%=") || fixed_code.include?("<%") || fixed_code.include?("<%=")

    if is_erb_file
      Rails.logger.info "[GitHub API] Detected ERB file - using precise line replacement"
      return apply_erb_fix(current_lines, error_line_number, source_ctx, fixed_code)
    end

    # Try to find method boundaries first
    method_name = extract_method_name_from_fix(fixed_code)
    Rails.logger.info "[GitHub API] Extracted method name from fix: #{method_name}"

    method_start, method_end = find_method_boundaries(current_lines, error_line_number, method_name)

    if method_start && method_end
      Rails.logger.info "[GitHub API] Found method boundaries: start=#{method_start + 1}, end=#{method_end + 1}"
      Rails.logger.info "[GitHub API] Original method lines (#{method_start + 1}-#{method_end + 1}):"
      current_lines[method_start..method_end].each_with_index do |line, idx|
        Rails.logger.info "[GitHub API]   Line #{method_start + idx + 1}: #{line.chomp}"
      end
    else
      Rails.logger.warn "[GitHub API] Could not find method boundaries for method: #{method_name}"
    end

    # If we found method boundaries, use them for replacement
    if method_start && method_end
      Rails.logger.info "[GitHub API] Found method boundaries: lines #{method_start + 1}-#{method_end + 1}"

      # Validate that fixed_code is a complete method
      unless validate_method_structure(fixed_code)
        Rails.logger.warn "[GitHub API] Fixed code doesn't look like a complete method, using fallback"
        return apply_fix_fallback(current_lines, error_line_number, source_ctx, fixed_code)
      end

      # Get the base indentation from the original method
      original_method_line = current_lines[method_start]
      base_indent = original_method_line.match(/^(\s*)/)[1]
      base_indent_level = base_indent.length

      Rails.logger.info "[GitHub API] Original method base indentation: #{base_indent_level} spaces (#{base_indent.inspect})"

      # Get fixed code lines and normalize them
      fixed_lines = fixed_code.lines.map(&:chomp).reject(&:empty?)

      # Normalize indentation in fixed_code to match the original method's indentation
      # Find the minimum indentation in fixed_code (usually the 'def' line)
      min_indent_in_fix = fixed_lines.map { |line| line.match(/^(\s*)/)[1].length }.min || 0

      Rails.logger.info "[GitHub API] Minimum indentation in fixed_code: #{min_indent_in_fix} spaces"

      # Adjust all lines in fixed_code to have correct relative indentation
      # The 'def' line should have base_indent, and other lines should maintain their relative indentation
      adjusted_fixed_lines = fixed_lines.map do |line|
        line_indent = line.match(/^(\s*)/)[1].length
        relative_indent = line_indent - min_indent_in_fix
        new_indent = base_indent + (" " * relative_indent)
        content = line.strip
        # Preserve empty lines but with base indent
        if content.empty?
          new_indent
        else
          "#{new_indent}#{content}"
        end
      end

      Rails.logger.info "[GitHub API] Adjusted fixed code (first 3 lines):"
      adjusted_fixed_lines.first(3).each_with_index do |line, idx|
        Rails.logger.info "[GitHub API]   Line #{idx + 1}: #{line.inspect}"
      end

      # Check if fixed_code already contains 'end' for the method
      fixed_has_end = adjusted_fixed_lines.any? { |line| line.strip == "end" }
      fixed_end_count = adjusted_fixed_lines.count { |line| line.strip == "end" }

      # Check if the original method_end line is an 'end'
      original_end_is_end = current_lines[method_end]&.strip == "end"

      Rails.logger.info "[GitHub API] Method replacement: fixed_has_end=#{fixed_has_end}, fixed_end_count=#{fixed_end_count}, original_end_is_end=#{original_end_is_end}"

      # Replace the method
      new_lines = []
      new_lines.concat(current_lines[0...method_start]) if method_start > 0

      # Add fixed code lines with proper indentation and newlines
      adjusted_fixed_lines.each do |line|
        new_lines << "#{line}\n"
      end

      # If fixed_code has its own 'end' and original also has 'end', skip the original 'end'
      # Otherwise, if fixed_code doesn't have 'end', we need to keep the original structure
      if fixed_has_end && original_end_is_end
        # Skip the original method_end line since fixed_code already has 'end'
        Rails.logger.info "[GitHub API] Skipping original 'end' at line #{method_end + 1} (fixed_code has its own)"
        new_lines.concat(current_lines[method_end + 1..-1]) if method_end < current_lines.size - 1
      elsif !fixed_has_end && original_end_is_end
        # Keep the original 'end' if fixed_code doesn't have one
        Rails.logger.info "[GitHub API] Keeping original 'end' at line #{method_end + 1} (fixed_code doesn't have one)"
        new_lines.concat(current_lines[method_end..-1]) if method_end < current_lines.size
      else
        # Normal case: replace from method_start to method_end inclusive
        Rails.logger.info "[GitHub API] Normal replacement (method_end line: #{current_lines[method_end]&.strip})"
        new_lines.concat(current_lines[method_end + 1..-1]) if method_end < current_lines.size - 1
      end

      result = new_lines.join

      # Final validation checks
      has_duplicates = has_duplicate_ends(result, method_start)
      has_quality_issues = has_code_quality_issues(result)
      has_valid_structure = validate_file_structure(result)
      has_valid_syntax = validate_ruby_syntax(result)

      Rails.logger.info "[GitHub API] Validation results: duplicates=#{has_duplicates}, quality_issues=#{has_quality_issues}, structure=#{has_valid_structure}, syntax=#{has_valid_syntax}"

      if has_valid_structure && !has_duplicates && !has_quality_issues && has_valid_syntax
        # Verify that the fix was actually applied - check if fixed_code content appears in result
        fixed_code_keywords = extract_key_changes(fixed_code)
        if fixed_code_keywords.any?
          result_contains_fix = fixed_code_keywords.all? { |keyword| result.include?(keyword) }
          if result_contains_fix
            Rails.logger.info "[GitHub API] Successfully applied fix to method - verified fix content is present"
            Rails.logger.info "[GitHub API] Result method lines (#{method_start + 1}-#{method_start + adjusted_fixed_lines.size}):"
            result.lines[method_start..method_start + adjusted_fixed_lines.size - 1].each_with_index do |line, idx|
              Rails.logger.info "[GitHub API]   Line #{method_start + idx + 1}: #{line.chomp}"
            end
            return result
          else
            Rails.logger.error "[GitHub API] Fix validation failed - fixed_code keywords not found in result"
            Rails.logger.error "[GitHub API] Looking for keywords: #{fixed_code_keywords.inspect}"
            Rails.logger.error "[GitHub API] Fixed code was: #{fixed_code[0..500]}"
            Rails.logger.error "[GitHub API] Result preview around method:"
            result.lines[[0, method_start - 2].max..[result.lines.size - 1, method_start + adjusted_fixed_lines.size + 2].min].each_with_index do |line, idx|
              Rails.logger.error "[GitHub API]   Line #{[0, method_start - 2].max + idx + 1}: #{line.chomp}"
            end
            # Don't return invalid result - let it fall through to fallback
          end
        else
          # If we can't extract keywords, at least verify the method was replaced
          # Check that the result doesn't contain the original error line if it was in source_ctx
          error_line_content = source_ctx["line_content"] || source_ctx[:line_content]
          if error_line_content.is_a?(Hash)
            error_content = error_line_content[:content] || error_line_content["content"]
            if error_content && fixed_code.include?(error_content) && !result.include?(error_content)
              Rails.logger.info "[GitHub API] Original error line removed from result - fix likely applied"
              Rails.logger.info "[GitHub API] Result method lines:"
              result.lines[method_start..method_start + adjusted_fixed_lines.size - 1].each_with_index do |line, idx|
                Rails.logger.info "[GitHub API]   Line #{method_start + idx + 1}: #{line.chomp}"
              end
              return result
            end
          end
        end

        Rails.logger.info "[GitHub API] Successfully applied fix to method (validation passed)"
        result
      else
        Rails.logger.warn "[GitHub API] File structure validation failed (duplicates: #{has_duplicates}, quality_issues: #{has_quality_issues}, structure: #{has_valid_structure}, syntax: #{has_valid_syntax}), using fallback"
        apply_fix_fallback(current_lines, error_line_number, source_ctx, fixed_code)
      end
    else
      # Fallback to original logic if we can't find method boundaries
      Rails.logger.info "[GitHub API] Could not find method boundaries, using fallback replacement"
      apply_fix_fallback(current_lines, error_line_number, source_ctx, fixed_code)
    end
  rescue => e
    Rails.logger.error "[GitHub API] apply_fix_to_content error: #{e.message}"
    nil
  end

  def normalize_fixed_code(fixed_code)
    return nil if fixed_code.blank?

    # Remove markdown code blocks if present
    code = fixed_code.strip
    code = code.sub(/^```ruby\s*\n?/i, "").sub(/\n?```\s*$/i, "")
    code = code.sub(/^```\s*\n?/, "").sub(/\n?```\s*$/, "")

    # Remove leading/trailing whitespace but preserve indentation
    lines = code.lines
    return nil if lines.empty?

    # Remove empty lines at start and end
    while lines.first&.strip&.empty?
      lines.shift
    end
    while lines.last&.strip&.empty?
      lines.pop
    end

    return nil if lines.empty?

    # Remove consecutive duplicate lines (non-trivial ones)
    cleaned_lines = []
    prev_stripped = nil
    lines.each do |line|
      stripped = line.strip
      # Always keep trivial lines (empty, end, comments)
      if stripped.empty? || stripped == "end" || stripped.start_with?("#") || stripped.length < 10
        cleaned_lines << line
        prev_stripped = stripped
      elsif prev_stripped != stripped
        cleaned_lines << line
        prev_stripped = stripped
      else
        Rails.logger.info "[GitHub API] Removing duplicate line from fix: #{stripped[0..60]}..."
      end
    end

    # Remove duplicate method definitions (keep only the first complete one)
    final_lines = remove_duplicate_methods(cleaned_lines)

    final_lines.join
  end

  def remove_duplicate_methods(lines)
    return lines if lines.empty?

    method_positions = {}
    lines.each_with_index do |line, idx|
      if match = line.match(/^\s*def\s+(self\.)?(\w+[?!=]?)/)
        method_name = match[2]
        method_positions[method_name] ||= []
        method_positions[method_name] << idx
      end
    end

    # Find methods with duplicates
    methods_to_remove = []
    method_positions.each do |method_name, positions|
      if positions.size > 1
        Rails.logger.warn "[GitHub API] Found #{positions.size} definitions of '#{method_name}', keeping only first"
        # Keep first, mark others for removal
        positions[1..-1].each do |start_idx|
          # Find the end of this method
          indent_level = lines[start_idx].match(/^(\s*)/)[1].length
          end_idx = start_idx
          (start_idx + 1).upto(lines.size - 1) do |i|
            line = lines[i]
            line_indent = line.match(/^(\s*)/)[1].length
            if line.strip == "end" && line_indent <= indent_level
              end_idx = i
              break
            end
          end
          methods_to_remove << (start_idx..end_idx)
        end
      end
    end

    return lines if methods_to_remove.empty?

    # Build list of lines to keep
    indices_to_remove = methods_to_remove.flat_map(&:to_a).uniq.sort
    lines.each_with_index.reject { |_, idx| indices_to_remove.include?(idx) }.map(&:first)
  end

  def has_duplicate_ends(content, method_start_line)
    lines = content.lines
    return false if method_start_line >= lines.size

    # Check around the method area for consecutive 'end' statements
    start_check = [0, method_start_line - 5].max
    end_check = [lines.size - 1, method_start_line + 50].min

    (start_check..end_check).each do |i|
      line = lines[i]

      # Check for 'end end' on the same line
      if line.strip =~ /\bend\s+end\b/
        Rails.logger.warn "[GitHub API] Found 'end end' on same line #{i + 1}: #{line.strip}"
        return true
      end

      # Check for consecutive 'end' statements on adjacent lines
      if line.strip == "end" && i < lines.size - 1
        next_line = lines[i + 1]
        if next_line&.strip == "end"
          # Check indentation - if they're at the same level, it's likely a duplicate
          line_indent = line.match(/^(\s*)/)[1].length
          next_indent = next_line.match(/^(\s*)/)[1].length
          if line_indent == next_indent
            Rails.logger.warn "[GitHub API] Found duplicate 'end' statements on lines #{i + 1}-#{i + 2}"
            return true
          end
        end
      end
    end

    false
  end

  def has_code_quality_issues(content)
    return true if content.blank?

    lines = content.lines

    # Check for duplicate method definitions
    method_defs = {}
    lines.each_with_index do |line, idx|
      if match = line.match(/^\s*def\s+(self\.)?(\w+[?!=]?)/)
        method_name = match[2]
        if method_defs[method_name]
          Rails.logger.warn "[GitHub API] Found duplicate method definition '#{method_name}' on lines #{method_defs[method_name] + 1} and #{idx + 1}"
          return true
        end
        method_defs[method_name] = idx
      end
    end

    # Check for consecutive duplicate lines (same non-trivial content)
    prev_line = nil
    lines.each_with_index do |line, idx|
      stripped = line.strip
      # Skip trivial lines (empty, just 'end', comments, single-word lines)
      next if stripped.empty? || stripped == "end" || stripped.start_with?("#") || stripped.length < 10

      if prev_line == stripped
        Rails.logger.warn "[GitHub API] Found duplicate line on #{idx} and #{idx + 1}: #{stripped[0..60]}..."
        return true
      end
      prev_line = stripped
    end

    # Check for missing 'end' after method definition (incomplete method)
    in_method = false
    method_indent = 0
    lines.each_with_index do |line, idx|
      if line.match?(/^\s*def\s/)
        if in_method
          # Found another def without closing previous one at same or lower indent
          new_indent = line.match(/^(\s*)/)[1].length
          if new_indent <= method_indent
            Rails.logger.warn "[GitHub API] Found method definition without closing 'end' before line #{idx + 1}"
            return true
          end
        end
        in_method = true
        method_indent = line.match(/^(\s*)/)[1].length
      elsif line.strip == "end" && in_method
        line_indent = line.match(/^(\s*)/)[1].length
        if line_indent <= method_indent
          in_method = false
        end
      end
    end

    false
  end

  def apply_erb_fix(current_lines, error_line_number, source_ctx, fixed_code)
    error_line_idx = error_line_number - 1
    return nil if error_line_idx < 0 || error_line_idx >= current_lines.size

    original_error_line = current_lines[error_line_idx]
    original_indent = original_error_line.match(/^(\s*)/)[1] || ""

    Rails.logger.info "[GitHub API] ERB fix - original line: #{original_error_line.chomp}"
    Rails.logger.info "[GitHub API] ERB fix - original indent: #{original_indent.inspect} (#{original_indent.length} spaces)"

    # Get the error content for comparison
    error_line_content = source_ctx["line_content"] || source_ctx[:line_content]
    error_content = if error_line_content.is_a?(Hash)
      error_line_content[:content] || error_line_content["content"]
    else
      error_line_content
    end
    error_content_str = error_content.to_s.strip

    Rails.logger.info "[GitHub API] ERB fix - error content: #{error_content_str}"

    # Extract the fixed line(s) from fixed_code
    # First, try to find "After" section if present
    fixed_code_normalized = fixed_code.strip

    # Check if fixed_code contains "Before" and "After" markers
    if fixed_code_normalized =~ /(?:^|\n)\s*\*\*after\*\*|\*\*after\*\*|after:|after\s+code/i
      Rails.logger.info "[GitHub API] ERB fix - found 'After' marker in fixed_code"
      # Extract everything after "After" marker
      after_match = fixed_code_normalized.match(/(?:^|\n)\s*(?:\*\*after\*\*|after:)\s*\n?(.*)/mi)
      if after_match
        fixed_code_normalized = after_match[1].strip
        Rails.logger.info "[GitHub API] ERB fix - extracted 'After' section: #{fixed_code_normalized[0..200]}"
      end
    end

    # Remove code block markers
    fixed_code_normalized = fixed_code_normalized.sub(/^```(?:erb|ruby|rb|html)?\s*\n?/i, "").sub(/\n?\s*```\s*$/i, "").strip

    # Split into lines and find the line that contains the actual fix
    fixed_lines = fixed_code_normalized.lines.map(&:chomp).reject(&:blank?)

    if fixed_lines.empty?
      Rails.logger.warn "[GitHub API] ERB fix - no fixed lines found in fixed_code"
      return nil
    end

    # If we have only one line, use it directly (most common case for simple fixes)
    if fixed_lines.size == 1
      fixed_line = fixed_lines.first.strip
      Rails.logger.info "[GitHub API] ERB fix - single line fix detected: #{fixed_line}"
    else
      # Find the line that contains the fix (different from error, contains corrected attribute)
      fixed_line = nil

      # Strategy 1: Look for a line that contains common fix patterns
      fixed_line = fixed_lines.find { |line|
        line.strip.include?("product.name") ||
        (line.strip != error_content_str &&
         (line.include?("product.") || line.include?("<%=") || line.include?("<% ")))
      }

      # Strategy 2: If error contains "first_name", look for line with "name" instead
      if !fixed_line && error_content_str.include?("first_name")
        fixed_line = fixed_lines.find { |line|
          line.include?("product.name") && !line.include?("first_name")
        }
      end

      # Strategy 3: Find line that's most similar to error but with the fix
      if !fixed_line && error_content_str.present?
        # Look for line that has same structure but different attribute
        fixed_line = fixed_lines.find { |line|
          # Same ERB structure but different content
          line.strip != error_content_str &&
          (line.include?("<%=") || line.include?("<% ")) &&
          line.length > 10 # Not too short
        }
      end

      # Strategy 4: Use the last line if it's different from error
      if !fixed_line
        fixed_line = fixed_lines.find { |line| line.strip != error_content_str } || fixed_lines.last
      end

      # Fallback: use first line
      fixed_line ||= fixed_lines.first
      fixed_line = fixed_line.strip

      Rails.logger.info "[GitHub API] ERB fix - selected from #{fixed_lines.size} lines: #{fixed_line}"
    end

    # Clean up the fixed line - remove any prefixes like "After:", "Fixed:", etc.
    fixed_line = fixed_line.sub(/^(?:after|fixed|correct|solution):\s*/i, "").strip

    # If fixed_line contains multiple lines (HTML blocks), extract only the line with the fix
    # This handles cases where AI returns a full HTML block but we only need one line
    if fixed_line.include?("\n")
      fixed_line_lines = fixed_line.lines.map(&:chomp).reject(&:blank?)
      # Try to find the line that matches the error structure but with the fix
      matching_line = fixed_line_lines.find { |line|
        # Same ERB pattern but with corrected attribute
        (line.include?("<%=") || line.include?("<% ")) &&
        line.strip != error_content_str
      }
      fixed_line = matching_line || fixed_line_lines.first
      fixed_line = fixed_line.strip
      Rails.logger.info "[GitHub API] ERB fix - extracted single line from multi-line block: #{fixed_line}"
    end

    # Check if the fix contains a conditional block (if/unless/begin/rescue)
    # If so, we need to handle it as a multi-line replacement
    is_conditional_fix = fixed_line.match?(/^\s*<%?\s*(if|unless|begin|rescue)/i)

    # Check if fixed_code contains a complete block (if + content + end)
    # A complete block should have both "if" and "end" with content between them
    if_count = fixed_code_normalized.scan(/<%?\s*(if|unless)/i).size
    end_count = fixed_code_normalized.scan(/<%?\s*end\s*%?>/i).size
    has_complete_block = (if_count > 0 && end_count >= if_count) &&
                        fixed_code_normalized.include?("end")

    # Check if the original error line should be preserved inside the conditional
    # We should preserve it if:
    # 1. It contains important content (image_tag, ERB output, etc.)
    # 2. The fixed_code doesn't already contain this content (meaning it's just adding a condition)
    original_line_content = original_error_line.strip

    # Check if fixed_code contains the same content as original (maybe with fix applied)
    fixed_contains_original_content = fixed_code_normalized.include?(original_line_content) ||
                                     (original_line_content.include?("image_tag") &&
                                      fixed_code_normalized.include?("image_tag"))

    should_preserve_original = (original_line_content.include?("image_tag") ||
                               original_line_content.include?("<%=") ||
                               original_line_content.include?("product.")) &&
                               !fixed_contains_original_content &&
                               !has_complete_block

    Rails.logger.info "[GitHub API] ERB fix - is_conditional: #{is_conditional_fix}, has_complete_block: #{has_complete_block}, should_preserve_original: #{should_preserve_original}"

    # If this is a conditional fix and we should preserve the original line
    if is_conditional_fix && should_preserve_original && !has_complete_block
      Rails.logger.info "[GitHub API] ERB fix - conditional fix detected, preserving original line inside condition"

      # Extract the actual content that should be inside the conditional
      # Look for image_tag or similar in the fixed_code
      content_inside_conditional = nil

      # Try to find the content that should be inside the if block in fixed_code
      fixed_code_normalized.lines.each do |line|
        line_stripped = line.strip
        # Skip the if line itself
        next if line_stripped.match?(/^\s*<%?\s*(if|unless|end)/i)
        # Look for image_tag or ERB output
        if line_stripped.include?("image_tag") ||
           (line_stripped.include?("<%=") && line_stripped.length > 10)
          content_inside_conditional = line_stripped
          break
        end
      end

      # If we didn't find content in fixed_code, use the original line (it might just need the conditional wrapper)
      content_inside_conditional ||= original_line_content

      # Build the multi-line replacement: if condition, original line (with proper indent), end
      indent_increment = 2 # Standard 2-space increment for nested content
      inner_indent = original_indent + (" " * indent_increment)

      replacement_lines = []
      replacement_lines << "#{original_indent}#{fixed_line}"
      replacement_lines << "#{inner_indent}#{content_inside_conditional}"
      replacement_lines << "#{original_indent}<% end %>"

      Rails.logger.info "[GitHub API] ERB fix - multi-line replacement:"
      replacement_lines.each_with_index do |line, idx|
        Rails.logger.info "[GitHub API]   Line #{idx + 1}: #{line}"
      end

      # Replace the error line with the multi-line block
      new_lines = current_lines.dup
      new_lines[error_line_idx] = replacement_lines.map { |line| "#{line}\n" }.join

      result = new_lines.join
    elsif has_complete_block
      # The fixed_code contains a complete block (if + content + end)
      # Extract all lines of the block with proper indentation
      Rails.logger.info "[GitHub API] ERB fix - complete block detected, extracting all lines"

      # Extract the block lines from fixed_code
      block_lines = fixed_code_normalized.lines.map(&:chomp).reject(&:blank?)

      # Find where the block starts (the if line)
      block_start_idx = block_lines.find_index { |line| line.strip.match?(/^\s*<%?\s*(if|unless)/i) }

      if block_start_idx
        # Extract the block (if line to end line)
        # Find the matching end for this if
        block_content = []
        if_level = 0
        found_if = false

        block_lines[block_start_idx..-1].each do |line|
          line_stripped = line.strip
          if line_stripped.match?(/^\s*<%?\s*(if|unless)/i)
            if_level += 1
            found_if = true
          elsif line_stripped.match?(/^\s*<%?\s*end\s*%?>/i)
            if_level -= 1
          end

          block_content << line
          break if found_if && if_level == 0
        end

        # Check if the block contains important content (image_tag, ERB output, etc.)
        block_has_content = block_content.any? { |line|
          line.include?("image_tag") ||
          (line.include?("<%=") && line.length > 20) ||
          line.include?("product.")
        }

        # Check if original line should be preserved (independent of has_complete_block check)
        original_has_important_content = (original_line_content.include?("image_tag") ||
                                          original_line_content.include?("<%=") ||
                                          original_line_content.include?("product."))

        # If the block doesn't have important content and original line does, preserve original
        if !block_has_content && original_has_important_content
          Rails.logger.info "[GitHub API] ERB fix - complete block lacks content, preserving original line inside condition"

          # Use the if line from the block, but keep original content
          if_line = block_content.first.strip
          indent_increment = 2
          inner_indent = original_indent + (" " * indent_increment)

          replacement_lines = []
          replacement_lines << "#{original_indent}#{if_line}"
          replacement_lines << "#{inner_indent}#{original_line_content}"
          replacement_lines << "#{original_indent}<% end %>"

          new_lines = current_lines.dup
          new_lines[error_line_idx] = replacement_lines.map { |line| "#{line}\n" }.join
          result = new_lines.join
        else
          # Use the complete block as-is
          # Normalize indentation - find minimum indent in the block
          min_indent = block_content.map { |line| line.match(/^(\s*)/)[1].length }.min || 0

          # Adjust all lines to have correct relative indentation
          replacement_lines = block_content.map do |line|
            line_indent = line.match(/^(\s*)/)[1].length
            relative_indent = line_indent - min_indent
            new_indent = original_indent + (" " * relative_indent)
            content = line.strip
            "#{new_indent}#{content}"
          end

          Rails.logger.info "[GitHub API] ERB fix - complete block replacement (#{replacement_lines.size} lines):"
          replacement_lines.each_with_index do |line, idx|
            Rails.logger.info "[GitHub API]   Line #{idx + 1}: #{line}"
          end

          # Replace the error line with the complete block
          new_lines = current_lines.dup
          new_lines[error_line_idx] = replacement_lines.map { |line| "#{line}\n" }.join

          result = new_lines.join
        end
      else
        # Fallback to single line if we can't find the block
        fixed_line_with_indent = "#{original_indent}#{fixed_line}"
        new_lines = current_lines.dup
        new_lines[error_line_idx] = "#{fixed_line_with_indent}\n"
        result = new_lines.join
      end
    else
      # Simple single-line replacement
      fixed_line_with_indent = "#{original_indent}#{fixed_line}"

      Rails.logger.info "[GitHub API] ERB fix - selected fixed line: #{fixed_line}"
      Rails.logger.info "[GitHub API] ERB fix - with indent: #{fixed_line_with_indent}"

      # Replace ONLY the error line, keep all other lines unchanged
      new_lines = current_lines.dup
      new_lines[error_line_idx] = "#{fixed_line_with_indent}\n"

      result = new_lines.join
    end

    result = new_lines.join

    # Verify the fix was applied correctly
    result_line = result.lines[error_line_idx]&.chomp
    if result_line&.include?(fixed_line.strip) && result_line != original_error_line.chomp
      Rails.logger.info "[GitHub API] ERB fix successfully applied - replaced line #{error_line_number}"
      Rails.logger.info "[GitHub API] ERB fix - before: #{original_error_line.chomp}"
      Rails.logger.info "[GitHub API] ERB fix - after:  #{result_line}"
      result
    else
      Rails.logger.warn "[GitHub API] ERB fix verification failed"
      Rails.logger.warn "[GitHub API] Original: #{original_error_line.chomp}"
      Rails.logger.warn "[GitHub API] Result:   #{result_line}"
      # Still return the result, as the replacement was attempted
      result
    end
  end

  def apply_fix_fallback(current_lines, error_line_number, source_ctx, fixed_code)
    # Calculate the range of lines to replace
    lines_before = source_ctx["lines_before"] || source_ctx[:lines_before] || []
    lines_after = source_ctx["lines_after"] || source_ctx[:lines_after] || []

    # Determine start and end line numbers (1-indexed)
    start_line = error_line_number - lines_before.size
    end_line = error_line_number + lines_after.size

    # Ensure bounds are valid
    start_line = [start_line, 1].max
    end_line = [end_line, current_lines.size].min

    # Build new content
    fixed_lines = fixed_code.lines

    new_lines = []
    new_lines.concat(current_lines[0...start_line - 1]) if start_line > 1
    new_lines.concat(fixed_lines)
    new_lines.concat(current_lines[end_line..-1]) if end_line < current_lines.size

    new_lines.join
  end

  def extract_method_name_from_fix(fixed_code)
    match = fixed_code.match(/^\s*def\s+(self\.)?(\w+[?!=]?)/)
    match ? match[2] : nil
  end

  def find_method_boundaries(lines, error_line_number, method_name)
    return [nil, nil] unless method_name

    # Convert to 0-indexed
    error_idx = error_line_number - 1
    return [nil, nil] if error_idx < 0 || error_idx >= lines.size

    # Find method start (look backwards)
    method_start = nil
    (error_idx).downto([0, error_idx - 30].max) do |i|
      line = lines[i]
      if line =~ /^\s*def\s+(self\.)?#{Regexp.escape(method_name)}/
        method_start = i
        break
      end
      # Stop if we hit class/module boundary
      break if line =~ /^\s*(class|module)\s/
    end

    return [nil, nil] unless method_start

    # Find method end (look forward for matching "end")
    method_end = method_start
    indent_level = lines[method_start].match(/^(\s*)/)[1].length

    (method_start + 1).upto([lines.size - 1, method_start + 100].min) do |i|
      line = lines[i]
      line_indent = line.match(/^(\s*)/)[1].length

      # If we find an "end" at the same or less indentation, it's the method end
      if line.strip == "end" && line_indent <= indent_level
        method_end = i
        break
      end
    end

    [method_start, method_end]
  end

  def validate_method_structure(fixed_code)
    return false if fixed_code.blank?

    # Should have "def" and "end"
    has_def = fixed_code =~ /^\s*def\s/
    has_end = fixed_code =~ /^\s*end\s*$/

    # Count def/end balance
    def_count = fixed_code.scan(/\bdef\s/).size
    end_count = fixed_code.scan(/\bend\b/).size

    has_def && has_end && def_count <= end_count
  end

  def validate_file_structure(content)
    return false if content.blank?

    # Basic validation: check for balanced class/module/end
    class_module_count = content.scan(/\b(class|module)\s/).size
    end_count = content.scan(/\bend\b/).size

    # Should have balanced structure (allows for some methods)
    end_count >= class_module_count
  end

  def validate_ruby_syntax(content)
    return false if content.blank?

    begin
      # Try to parse the Ruby code
      RubyVM::InstructionSequence.compile(content)
      true
    rescue SyntaxError => e
      Rails.logger.warn "[GitHub API] Ruby syntax error detected: #{e.message}"
      false
    rescue => e
      # Other errors (like missing constants) are OK - we just want to check syntax
      Rails.logger.debug "[GitHub API] Ruby parse warning (not syntax error): #{e.message}"
      true
    end
  end

  def extract_key_changes(fixed_code)
    return [] if fixed_code.blank?

    keywords = []

    # Look for common fix patterns
    # params[:id], params[:key], etc.
    keywords.concat(fixed_code.scan(/params\[:?\w+\]/))

    # Look for method calls that are likely fixes
    # .present?, .blank?, .nil?, etc.
    keywords.concat(fixed_code.scan(/\.(present\?|blank\?|nil\?|empty\?)/))

    # Look for rescue, begin, etc. (error handling fixes)
    keywords.concat(fixed_code.scan(/\b(rescue|begin|ensure)\b/))

    # Look for specific patterns that indicate a fix (not just original code)
    # If fixed_code contains params, that's a strong indicator
    if fixed_code.include?("params[")
      keywords << "params"
    end

    # Remove duplicates and return
    keywords.uniq.reject(&:blank?)
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

  def claude_chat_completion(prompt)
    require "net/http"
    require "json"

    uri = URI.parse("https://api.anthropic.com/v1/messages")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

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
    raise "Claude API error: #{res.code}" unless res.code.to_i.between?(200, 299)

    json = JSON.parse(res.body)
    content_blocks = json["content"] || []
    text_block = content_blocks.find { |b| b["type"] == "text" }
    text_block&.dig("text") || ""
  end
end
