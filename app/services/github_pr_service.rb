class GithubPrService
  def initialize(project)
    @project = project
    settings = @project.settings || {}
    @github_repo = settings["github_repo"].to_s.gsub(%r{^/|/$}, "") # e.g., "owner/repo" - strip slashes
    @base_branch_override = settings["github_base_branch"]
    # Token precedence: per-project PAT > installation token > env PAT
    @project_pat = settings["github_pat"]
    @installation_id = settings["github_installation_id"]
    @env_pat = ENV["GITHUB_TOKEN"]
    # App creds precedence: per-project > env
    @project_app_id = settings["github_app_id"]
    @project_app_pk = settings["github_app_pk"]
    @env_app_id = ENV["AR_GH_APP_ID"]
    @env_app_pk = ENV["AR_GH_APP_PK"]
    @openai_key = ENV["OPENAI_API_KEY"]
  end

  def create_n_plus_one_fix_pr(sql_fingerprint)
    return { success: false, error: "GitHub integration not configured" } unless configured?

    begin
      # Generate optimization suggestions
      suggestions = generate_optimization_suggestions(sql_fingerprint)

      # Create branch name
      branch_name = "fix/n-plus-one-#{sql_fingerprint.id}-#{Time.current.to_i}"

      # This is where you would integrate with GitHub API
      # For now, we'll return a mock response

      {
        success: true,
        pr_url: "https://github.com/#{@github_repo}/pull/123",
        branch_name: branch_name,
        suggestions: suggestions
      }
    rescue => e
      Rails.logger.error "GitHub PR creation failed: #{e.message}"
      { success: false, error: e.message }
    end
  end

  private

  def configured?
    (@project_pat.present? || @installation_id.present? || @env_pat.present?) && @github_repo.present?
  end

  # Minimal flow: create a branch off default, create a draft PR with RCA body
  public

  def create_pr_for_issue(issue)
    return { success: false, error: "GitHub integration not configured" } unless configured?

    owner, repo = @github_repo.split("/", 2)

    token = @project_pat.presence || generate_installation_token(@installation_id) || @env_pat
    return { success: false, error: "Failed to acquire GitHub token" } unless token.present?

    base_branch = @base_branch_override.presence || detect_default_branch(owner, repo, token) || "main"
    Rails.logger.info "[GitHub API] Using base_branch=#{base_branch} for #{owner}/#{repo}"

    # Git refs endpoint uses 'refs' (plural)
    ref_response = github_get("/repos/#{owner}/#{repo}/git/refs/heads/#{base_branch}", token)
    Rails.logger.info "[GitHub API] Ref response: #{ref_response.inspect}"
    head_sha = ref_response&.dig("object", "sha")
    unless head_sha
      # Try alternate branch names
      alt_branch = base_branch == "main" ? "master" : "main"
      Rails.logger.info "[GitHub API] Trying alternate branch: #{alt_branch}"
      ref_response = github_get("/repos/#{owner}/#{repo}/git/refs/heads/#{alt_branch}", token)
      head_sha = ref_response&.dig("object", "sha")
      base_branch = alt_branch if head_sha
    end
    return { success: false, error: "Base branch not found (tried: main, master). Check repo access." } unless head_sha

    branch = "ar/fix-issue-#{issue.id}-#{Time.now.to_i}"
    Rails.logger.info "[GitHub API] Creating branch #{branch} from sha=#{head_sha[0, 7]}"
    ref_resp = github_post("/repos/#{owner}/#{repo}/git/refs", token, {
      ref: "refs/heads/#{branch}",
      sha: head_sha
    })
    return { success: false, error: ref_resp[:error] } if ref_resp.is_a?(Hash) && ref_resp[:error]

    # Generate AI-powered PR content with code fix
    pr_content = generate_pr_content(issue)
    pr_title = pr_content[:title]
    pr_body = pr_content[:body]
    code_fix = pr_content[:code_fix]

    # Create commit with suggested fix if available
    commit_result = create_fix_commit(owner, repo, token, branch, head_sha, issue, code_fix, pr_body)
    if commit_result.is_a?(Hash) && commit_result[:error]
      return { success: false, error: commit_result[:error] }
    end

    pr = github_post("/repos/#{owner}/#{repo}/pulls", token, {
      title: pr_title,
      head: branch,
      base: base_branch,
      body: pr_body,
      draft: true
    })

    if pr.is_a?(Hash) && pr["html_url"]
      Rails.logger.info "[GitHub API] PR created url=#{pr['html_url']}"
      { success: true, pr_url: pr["html_url"], branch_name: branch }
    else
      { success: false, error: pr[:error] || "Unknown PR error" }
    end
  rescue => e
    Rails.logger.error "GitHub PR creation failed: #{e.class}: #{e.message}"
    { success: false, error: e.message }
  end

  # Generate AI-powered PR content with title, body, and code fix
  def generate_pr_content(issue)
    sample_event = issue.events.order(occurred_at: :desc).first

    # If we have existing AI summary, parse it for the fix section
    if issue.ai_summary.present?
      parsed = parse_ai_summary(issue.ai_summary)
      title = generate_pr_title(issue, parsed[:root_cause])
      body = build_enhanced_pr_body(issue, sample_event, parsed)
      code_fix = parsed[:fix_code]

      { title: title, body: body, code_fix: code_fix }
    elsif @openai_key.present?
      # Generate fresh AI analysis for the PR
      ai_result = generate_ai_pr_analysis(issue, sample_event)
      title = ai_result[:title] || "Fix #{issue.exception_class} in #{issue.controller_action}"
      body = ai_result[:body] || build_basic_pr_body(issue, sample_event)
      code_fix = ai_result[:code_fix]

      { title: title, body: body, code_fix: code_fix }
    else
      # Fallback to basic content
      {
        title: "Fix #{issue.exception_class} in #{issue.controller_action}",
        body: build_basic_pr_body(issue, sample_event),
        code_fix: nil
      }
    end
  end

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
    result = { root_cause: nil, fix: nil, fix_code: nil, prevention: nil }
    return result if summary.blank?

    # Parse markdown sections from AI summary
    sections = summary.split(/^##\s+/m)

    sections.each do |section|
      if section.start_with?("Root Cause")
        result[:root_cause] = section.sub(/^Root Cause\s*\n/, "").strip
      elsif section.start_with?("Fix")
        fix_content = section.sub(/^Fix\s*\n/, "").strip
        result[:fix] = fix_content

        # Extract code blocks from the fix section
        code_blocks = fix_content.scan(/```(?:ruby|rb)?\s*(.*?)```/m).flatten
        result[:fix_code] = code_blocks.first if code_blocks.any?
      elsif section.start_with?("Prevention")
        result[:prevention] = section.sub(/^Prevention\s*\n/, "").strip
      end
    end

    result
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

  # Generate AI-powered PR analysis using OpenAI
  def generate_ai_pr_analysis(issue, sample_event)
    return {} unless @openai_key.present?

    prompt = build_pr_prompt(issue, sample_event)

    begin
      response = openai_chat_completion(prompt)
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

  def openai_chat_completion(prompt)
    require "net/http"
    require "json"

    uri = URI.parse("https://api.openai.com/v1/chat/completions")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30

    body = {
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: "You are a senior Rails developer helping fix bugs. Be concise and practical." },
        { role: "user", content: prompt }
      ],
      temperature: 0.3,
      max_tokens: 2000
    }

    req = Net::HTTP::Post.new(uri.request_uri)
    req["Authorization"] = "Bearer #{@openai_key}"
    req["Content-Type"] = "application/json"
    req.body = JSON.dump(body)

    res = http.request(req)
    raise "OpenAI error: #{res.code}" unless res.code.to_i.between?(200, 299)

    json = JSON.parse(res.body)
    json.dig("choices", 0, "message", "content")
  end

  # Create a commit with actual code fix or fallback to suggestion file
  def create_fix_commit(owner, repo, token, branch, base_sha, issue, code_fix, pr_body)
    # Get base commit tree
    base_commit = github_get("/repos/#{owner}/#{repo}/git/commits/#{base_sha}", token)
    base_tree_sha = base_commit.is_a?(Hash) ? base_commit["tree"]&.dig("sha") : nil
    return { error: "Failed to read base commit" } unless base_tree_sha

    tree_entries = []
    commit_msg_parts = []

    # Try to apply actual code fix to the source file
    sample_event = issue.events.order(occurred_at: :desc).first
    actual_fix_applied = false

    if sample_event&.has_structured_stack_trace?
      fix_result = try_apply_actual_fix(owner, repo, token, sample_event, issue)
      if fix_result[:success]
        tree_entries << fix_result[:tree_entry]
        commit_msg_parts << "fix: #{fix_result[:file_path]}"
        actual_fix_applied = true
        Rails.logger.info "[GitHub API] Applied actual code fix to #{fix_result[:file_path]}"
      else
        Rails.logger.info "[GitHub API] Could not apply actual fix: #{fix_result[:reason]}"
      end
    end

    # Always add the context/suggestion file
    fix_file_content = build_fix_file_content(issue, code_fix, pr_body, actual_fix_applied)
    blob = github_post("/repos/#{owner}/#{repo}/git/blobs", token, {
      content: fix_file_content,
      encoding: "utf-8"
    })
    blob_sha = blob.is_a?(Hash) ? blob["sha"] : nil
    return { error: "Failed to create blob" } unless blob_sha

    tree_entries << { path: ".activerabbit/fixes/issue-#{issue.id}-fix.md", mode: "100644", type: "blob", sha: blob_sha }

    # Create tree with all entries
    tree = github_post("/repos/#{owner}/#{repo}/git/trees", token, {
      base_tree: base_tree_sha,
      tree: tree_entries
    })
    new_tree_sha = tree.is_a?(Hash) ? tree["sha"] : nil
    return { error: "Failed to create tree" } unless new_tree_sha

    # Create commit
    if actual_fix_applied
      commit_msg = "fix: #{issue.exception_class} in #{issue.controller_action.to_s.split('#').last}\n\n#{commit_msg_parts.join("\n")}"
    else
      commit_msg = "fix: add suggested fix for #{issue.exception_class} (Issue ##{issue.id})"
    end

    commit = github_post("/repos/#{owner}/#{repo}/git/commits", token, {
      message: commit_msg,
      tree: new_tree_sha,
      parents: [base_sha]
    })
    new_commit_sha = commit.is_a?(Hash) ? commit["sha"] : nil
    return { error: "Failed to create commit" } unless new_commit_sha

    # Update branch ref
    ref_update = github_patch("/repos/#{owner}/#{repo}/git/refs/heads/#{branch}", token, {
      sha: new_commit_sha,
      force: false
    })
    if ref_update.is_a?(Hash) && ref_update[:error]
      return { error: ref_update[:error] }
    end

    Rails.logger.info "[GitHub API] Created fix commit #{new_commit_sha[0, 7]} on #{branch} (actual_fix: #{actual_fix_applied})"
    { success: true, commit_sha: new_commit_sha, actual_fix_applied: actual_fix_applied }
  end

  # Try to apply actual code fix to the source file
  def try_apply_actual_fix(owner, repo, token, sample_event, issue)
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

    # Fetch current file content from GitHub
    file_response = github_get("/repos/#{owner}/#{repo}/contents/#{normalized_path}", token)
    return { success: false, reason: "File not found in repo: #{normalized_path}" } unless file_response.is_a?(Hash) && file_response["content"]

    current_content = Base64.decode64(file_response["content"])
    current_lines = current_content.lines

    # Generate the fixed code using AI
    fixed_code = generate_code_fix(issue, sample_event, error_frame, current_content)
    return { success: false, reason: "AI could not generate fix" } unless fixed_code

    # Apply the fix to the file content
    new_content = apply_fix_to_content(current_lines, line_number, source_ctx, fixed_code)
    return { success: false, reason: "Could not apply fix to file" } unless new_content && new_content != current_content

    # Create blob with new content
    blob = github_post("/repos/#{owner}/#{repo}/git/blobs", token, {
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

  def normalize_file_path(path)
    return nil if path.blank?

    # Remove common prefixes
    path = path.sub(%r{^\./}, "")                    # Remove ./
    path = path.sub(%r{^/app/}, "app/")              # /app/ -> app/
    path = path.sub(%r{^.*/app/}, "app/")            # .../app/ -> app/
    path = path.sub(%r{^.*/lib/}, "lib/")            # .../lib/ -> lib/
    path = path.sub(%r{^.*/config/}, "config/")      # .../config/ -> config/

    # If it still has absolute-looking path, try to extract from common Rails structure
    if path.start_with?("/")
      match = path.match(%r{/(app|lib|config|spec|test)/.*$})
      path = match[0].sub(%r{^/}, "") if match
    end

    path.presence
  end

  # Generate actual code fix using AI
  def generate_code_fix(issue, sample_event, error_frame, file_content)
    return nil unless @openai_key.present?

    source_ctx = error_frame["source_context"] || error_frame[:source_context]
    line_number = error_frame["line"] || error_frame[:line]
    method_name = error_frame["method"] || error_frame[:method]

    # Build focused prompt for code fix
    prompt = <<~PROMPT
      Fix this Ruby code error. Return ONLY the fixed code block, no explanation.

      Error: #{issue.exception_class}
      Message: #{issue.sample_message}
      File: #{error_frame["file"]}
      Line: #{line_number}
      Method: #{method_name}

      Current code around error (line #{line_number} is the error):
      ```ruby
      #{format_source_for_prompt(source_ctx)}
      ```

      Return the fixed version of ONLY these lines (about 5-15 lines).
      Do not include ```ruby markers, just the code.
      Make minimal changes to fix the error.
    PROMPT

    begin
      response = openai_chat_completion(prompt)
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

  # Apply the AI-generated fix to the file content
  def apply_fix_to_content(current_lines, error_line_number, source_ctx, fixed_code)
    return nil if fixed_code.blank?

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
  rescue => e
    Rails.logger.error "[GitHub API] apply_fix_to_content error: #{e.message}"
    nil
  end

  def build_fix_file_content(issue, code_fix, pr_body, actual_fix_applied = false)
    lines = []
    lines << "# Fix for #{issue.exception_class}"
    lines << ""
    lines << "**Issue ID:** #{issue.id}"
    lines << "**Generated:** #{Time.current.strftime('%Y-%m-%d %H:%M UTC')}"

    if actual_fix_applied
      lines << "**Status:** ✅ Code fix automatically applied"
      lines << ""
      lines << "> **Note:** An actual code fix has been applied to the source file in this PR."
      lines << "> Please review the changes carefully before merging."
    else
      lines << "**Status:** 📋 Suggestion only (manual review required)"
    end
    lines << ""

    if code_fix.present? && !actual_fix_applied
      lines << "## Suggested Code Fix"
      lines << ""
      lines << "```ruby"
      lines << code_fix
      lines << "```"
      lines << ""
    end

    lines << "## Full Analysis"
    lines << ""
    lines << pr_body
    lines << ""
    lines << "---"
    lines << "_Generated by [ActiveRabbit](https://activerabbit.ai) AI_"

    lines.join("\n")
  end

  def generate_installation_token(installation_id)
    return nil unless installation_id.present?
    # Prefer per-project app creds; fallback to env.
    app_id = @project_app_id.presence || @env_app_id
    pk_pem = @project_app_pk.presence || @env_app_pk
    return nil unless app_id.present? && pk_pem.present?

    jwt = generate_app_jwt(app_id, pk_pem)
    resp = http_post_json("https://api.github.com/app/installations/#{installation_id}/access_tokens", nil, { "Authorization" => "Bearer #{jwt}", "Accept" => "application/vnd.github+json" })
    resp&.dig("token")
  end

  def generate_app_jwt(app_id, pk_pem)
    require "openssl"
    require "jwt"
    private_key = OpenSSL::PKey::RSA.new(pk_pem)
    payload = { iat: Time.now.to_i - 60, exp: Time.now.to_i + (10 * 60), iss: app_id.to_i }
    JWT.encode(payload, private_key, "RS256")
  end

  def github_get(path, token)
    http_json("https://api.github.com#{path}", { "Authorization" => "Bearer #{token}", "Accept" => "application/vnd.github+json" })
  end

  def github_post(path, token, body)
    http_post_json("https://api.github.com#{path}", body, { "Authorization" => "Bearer #{token}", "Accept" => "application/vnd.github+json" })
  end

  def github_patch(path, token, body)
    http_patch_json("https://api.github.com#{path}", body, { "Authorization" => "Bearer #{token}", "Accept" => "application/vnd.github+json" })
  end

  def detect_default_branch(owner, repo, token)
    repo_json = github_get("/repos/#{owner}/#{repo}", token)
    Rails.logger.info "[GitHub API] Repo response keys: #{repo_json.keys rescue 'error'}"
    if repo_json.is_a?(Hash) && repo_json["message"]
      Rails.logger.error "[GitHub API] Error getting repo: #{repo_json['message']}"
      return nil
    end
    default_branch = repo_json.is_a?(Hash) ? repo_json["default_branch"] : nil
    Rails.logger.info "[GitHub API] default_branch=#{default_branch.inspect} for #{owner}/#{repo}"
    default_branch
  rescue => e
    Rails.logger.error "[GitHub API] detect_default_branch error: #{e.message}"
    nil
  end

  def http_json(url, headers)
    require "net/http"
    require "json"
    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    headers.each { |k, v| req[k] = v }
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    Rails.logger.info "[GitHub API] GET #{uri.path} status=#{res.code}"
    JSON.parse(res.body)
  end

  def http_post_json(url, body, headers)
    require "net/http"
    require "json"
    uri = URI(url)
    req = Net::HTTP::Post.new(uri)
    headers.each { |k, v| req[k] = v }
    req.body = body ? JSON.generate(body) : ""
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    Rails.logger.info "[GitHub API] POST #{uri.path} status=#{res.code}"
    return { error: "HTTP #{res.code}" } if res.code.to_i >= 400
    JSON.parse(res.body) rescue {}
  end

  def http_patch_json(url, body, headers)
    require "net/http"
    require "json"
    uri = URI(url)
    req = Net::HTTP::Patch.new(uri)
    headers.each { |k, v| req[k] = v }
    req.body = body ? JSON.generate(body) : ""
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    Rails.logger.info "[GitHub API] PATCH #{uri.path} status=#{res.code}"
    return { error: "HTTP #{res.code}" } if res.code.to_i >= 400
    JSON.parse(res.body) rescue {}
  end


  def generate_optimization_suggestions(sql_fingerprint)
    query = sql_fingerprint.normalized_query
    controller_action = sql_fingerprint.controller_action

    suggestions = []

    # Detect common N+1 patterns and suggest fixes
    if query.include?("SELECT") && controller_action
      if query.match?(/users.*id = \?/i)
        suggestions << {
          type: "eager_loading",
          suggestion: "Consider adding `includes(:user)` to your query in #{controller_action}",
          code_example: "# Instead of:\n# @records.each { |r| r.user.name }\n\n# Use:\n# @records = @records.includes(:user)\n# @records.each { |r| r.user.name }"
        }
      end

      if query.match?(/SELECT.*FROM.*WHERE.*id = \?/i)
        suggestions << {
          type: "batch_loading",
          suggestion: "Consider using `preload` or `includes` to batch load associations",
          code_example: "# Use eager loading to reduce database queries:\n# Model.includes(:association).where(...)"
        }
      end
    end

    # Add indexing suggestions
    if sql_fingerprint.avg_duration_ms > 100
      suggestions << {
        type: "indexing",
        suggestion: "Consider adding database indexes to improve query performance",
        code_example: "# Add migration:\n# add_index :table_name, :column_name"
      }
    end

    suggestions
  end

end
