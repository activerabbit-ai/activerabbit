# frozen_string_literal: true

module Github
  class PrService
    def initialize(project)
      @project = project
      settings = @project.settings || {}
      @github_repo = settings["github_repo"].to_s.gsub(%r{^/|/$}, "") # e.g., "owner/repo" - strip slashes
      @base_branch_override = settings["github_base_branch"]  # PR target branch (merge into)
      @source_branch_override = settings["github_source_branch"]  # Branch to fork from
      # Token precedence: per-project PAT > installation token > env PAT
      @project_pat = settings["github_pat"]
      @installation_id = settings["github_installation_id"]
      @env_pat = ENV["GITHUB_TOKEN"]
      # App creds precedence: per-project > env
      @project_app_id = settings["github_app_id"]
      @project_app_pk = settings["github_app_pk"]
      @env_app_id = ENV["AR_GH_APP_ID"]
      @env_app_pk = Github::TokenManager.resolve_env_private_key
      @anthropic_key = ENV["ANTHROPIC_API_KEY"]

      # Initialize service dependencies
      @token_manager = Github::TokenManager.new(
        project_pat: @project_pat,
        installation_id: @installation_id,
        env_pat: @env_pat,
        project_app_id: @project_app_id,
        project_app_pk: @project_app_pk,
        env_app_id: @env_app_id,
        env_app_pk: @env_app_pk
      )
      @branch_name_generator = Github::BranchNameGenerator.new(anthropic_key: @anthropic_key)
      @pr_content_generator = Github::PrContentGenerator.new(anthropic_key: @anthropic_key)
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

    def reopen_pr(pr_url)
      return { success: false, error: "GitHub integration not configured" } unless configured?
      return { success: false, error: "No PR URL provided" } if pr_url.blank?

      pr_number = extract_pr_number(pr_url)
      return { success: false, error: "Could not parse PR number from URL" } unless pr_number

      owner, repo = @github_repo.split("/", 2)
      token = @token_manager.get_token
      return { success: false, error: "Failed to acquire GitHub token" } unless token.present?

      api_client = Github::ApiClient.new(token)
      pr_info = api_client.get_pr_info(owner, repo, pr_number)
      return { success: false, error: "PR ##{pr_number} not found" } unless pr_info

      if pr_info[:merged]
        return { success: false, error: "PR ##{pr_number} has already been merged and cannot be reopened" }
      end

      # If the PR has 0 changed files, the fix was never applied — close the
      # empty PR and create a brand-new one that will attempt the fix again.
      if pr_info[:changed_files] == 0
        Rails.logger.info "[GitHub API] PR ##{pr_number} has 0 changed files, replacing with a new PR"
        api_client.close_pr(owner, repo, pr_number) if pr_info[:state] == "open"
        issue = find_issue_by_pr_url(pr_url)
        if issue
          new_result = create_pr_for_issue(issue)
          if new_result[:success]
            update_stored_pr_url(issue, new_result[:pr_url])
            schedule_auto_merge(issue, new_result)
          end
          return new_result
        end
        return { success: false, error: "PR ##{pr_number} has no file changes and the associated issue could not be found" }
      end

      if pr_info[:state] == "open"
        if pr_info[:draft] && @project.auto_merge_enabled?
          api_client.mark_pr_ready(owner, repo, pr_number)
          Rails.logger.info "[GitHub API] Marked PR ##{pr_number} as ready for review"
        end
        schedule_auto_merge_for_existing_pr(find_issue_by_pr_url(pr_url), pr_info)
        return { success: true, pr_url: pr_info[:html_url], already_open: true }
      end

      result = api_client.reopen_pr(owner, repo, pr_number)
      if result.is_a?(Hash) && result[:error]
        Rails.logger.info "[GitHub API] Reopen failed (#{result[:error]}), creating new PR for issue"
        issue = find_issue_by_pr_url(pr_url)
        if issue
          new_result = create_pr_for_issue(issue)
          if new_result[:success]
            update_stored_pr_url(issue, new_result[:pr_url])
            schedule_auto_merge(issue, new_result)
          end
          return new_result
        end
        return { success: false, error: "Could not reopen PR ##{pr_number}: #{result[:error]}. Branch may have been deleted — use 'Create PR' to generate a new fix." }
      end

      schedule_auto_merge_for_existing_pr(find_issue_by_pr_url(pr_url), pr_info)

      if @project.auto_merge_enabled?
        api_client.mark_pr_ready(owner, repo, pr_number)
      end

      Rails.logger.info "[GitHub API] Reopened PR ##{pr_number} at #{pr_info[:html_url]}"
      { success: true, pr_url: pr_info[:html_url], reopened: true }
    rescue => e
      Rails.logger.error "GitHub PR reopen failed: #{e.class}: #{e.message}"
      { success: false, error: e.message }
    end

    def pr_state(pr_url)
      return nil if pr_url.blank? || !configured?

      pr_number = extract_pr_number(pr_url)
      return nil unless pr_number

      owner, repo = @github_repo.split("/", 2)
      token = @token_manager.get_token
      return nil unless token.present?

      api_client = Github::ApiClient.new(token)
      api_client.get_pr_info(owner, repo, pr_number)
    rescue => e
      Rails.logger.error "GitHub PR state check failed: #{e.class}: #{e.message}"
      nil
    end

    def create_pr_for_issue(issue, custom_branch_name: nil)
      return { success: false, error: "GitHub integration not configured" } unless configured?

      owner, repo = @github_repo.split("/", 2)

      token = @token_manager.get_token
      return { success: false, error: "Failed to acquire GitHub token" } unless token.present?

      api_client = Github::ApiClient.new(token)
      default_branch = api_client.detect_default_branch(owner, repo) || "main"

      # Source branch: where to fork new branch FROM (for getting latest code)
      # Use source_branch setting, fall back to base_branch, then default
      source_branch = @source_branch_override.presence || @base_branch_override.presence || default_branch

      # Base branch: where PR will be merged INTO
      base_branch = @base_branch_override.presence || default_branch

      Rails.logger.info "[GitHub API] Using source_branch=#{source_branch}, base_branch=#{base_branch} for #{owner}/#{repo}"

      # Get SHA from source branch (this is where we fork the new branch from)
      ref_response = api_client.get("/repos/#{owner}/#{repo}/git/refs/heads/#{source_branch}")
      Rails.logger.info "[GitHub API] Ref response: #{ref_response.inspect}"
      Rails.logger.info "GitHub token present? #{@project_pat.present?}"
      head_sha = ref_response&.dig("object", "sha")
      unless head_sha
        # Try alternate branch names
        alt_branch = source_branch == "main" ? "master" : "main"
        Rails.logger.info "[GitHub API] Trying alternate branch: #{alt_branch}"
        ref_response = api_client.get("/repos/#{owner}/#{repo}/git/refs/heads/#{alt_branch}")
        head_sha = ref_response&.dig("object", "sha")
        source_branch = alt_branch if head_sha
      end

      # Better error message with tried branches
      unless head_sha
        tried_branches = [@source_branch_override, @base_branch_override, "main", "master"].compact.uniq.join(", ")
        return { success: false, error: "Source branch not found (tried: #{tried_branches}). Check repository access and set the correct branch in project settings." }
      end

      # Generate branch name: use custom, or generate via AI, or fallback
      branch = @branch_name_generator.generate(issue, custom_branch_name)
      Rails.logger.info "[GitHub API] Creating branch #{branch} from sha=#{head_sha[0, 7]}"
      ref_resp = api_client.post("/repos/#{owner}/#{repo}/git/refs", {
        ref: "refs/heads/#{branch}",
        sha: head_sha
      })
      return { success: false, error: ref_resp[:error] } if ref_resp.is_a?(Hash) && ref_resp[:error]

      # Generate AI-powered PR content with code fix
      pr_content = @pr_content_generator.generate(issue)
      pr_title = pr_content[:title]
      pr_body = pr_content[:body]
      code_fix = pr_content[:code_fix]
      before_code = pr_content[:before_code]
      file_fixes = pr_content[:file_fixes] || []

      # Create commit with suggested fix if available
      # Use SimpleCodeFixApplier for reliable line-based fixes
      code_fix_applier = Github::SimpleCodeFixApplier.new(api_client: api_client, anthropic_key: @anthropic_key, source_branch: source_branch)
      commit_result = create_fix_commit(api_client, code_fix_applier, owner, repo, branch, head_sha, issue, code_fix, before_code, pr_body, file_fixes)
      if commit_result.is_a?(Hash) && commit_result[:error]
        return { success: false, error: commit_result[:error] }
      end

      # Track if actual fix was applied from commit result
      actual_fix_applied = commit_result.is_a?(Hash) && commit_result[:actual_fix_applied]
      unapplied_fixes = commit_result.is_a?(Hash) ? (commit_result[:unapplied_fixes] || []) : []

      unless actual_fix_applied
        manual_review_banner = <<~BANNER
          > **⚠️ Needs Manual Review** — The AI-generated code fix could not be applied automatically.
          > Please review the suggested fix in the description below and apply it manually.

        BANNER
        pr_body = manual_review_banner + pr_body
        pr_title = "[Review Needed] #{pr_title}"
      end

      if unapplied_fixes.any?
        pr_body += unapplied_fixes_section(unapplied_fixes)
      end

      pr = api_client.post("/repos/#{owner}/#{repo}/pulls", {
        title: pr_title,
        head: branch,
        base: base_branch,
        body: pr_body,
        draft: !@project.auto_merge_enabled?
      })

      if pr.is_a?(Hash) && pr["html_url"]
        Rails.logger.info "[GitHub API] PR created url=#{pr['html_url']} (actual_fix_applied=#{actual_fix_applied})"
        { success: true, pr_url: pr["html_url"], branch_name: branch, actual_fix_applied: actual_fix_applied }
      else
        { success: false, error: pr[:error] || "Unknown PR error" }
      end
    rescue => e
      Rails.logger.error "GitHub PR creation failed: #{e.class}: #{e.message}"
      { success: false, error: e.message }
    end

    private

    def configured?
      @token_manager.configured? && @github_repo.present?
    end

    def find_issue_by_pr_url(pr_url)
      settings = @project.settings || {}
      issue_pr_urls = settings["issue_pr_urls"] || {}
      issue_id = issue_pr_urls.key(pr_url)
      return nil unless issue_id

      @project.issues.find_by(id: issue_id)
    end

    def extract_pr_number(pr_url)
      match = pr_url.to_s.match(%r{/pull/(\d+)})
      match[1].to_i if match
    end

    # Convert "TaskSheet::SubmittedEvaluationsController#index" →
    #         "app/controllers/task_sheet/submitted_evaluations_controller.rb"
    def infer_file_path_from_controller(controller_action)
      return nil if controller_action.blank?

      controller_part = controller_action.to_s.split("#").first
      return nil if controller_part.blank?

      path = controller_part.underscore
      path = "app/controllers/#{path}.rb" unless path.start_with?("app/")
      path
    rescue => e
      Rails.logger.debug "[PrService] Could not infer file path from #{controller_action}: #{e.message}"
      nil
    end

    def update_stored_pr_url(issue, new_pr_url)
      settings = @project.settings || {}
      issue_pr_urls = settings["issue_pr_urls"] || {}
      issue_pr_urls[issue.id.to_s] = new_pr_url
      settings["issue_pr_urls"] = issue_pr_urls
      @project.update_column(:settings, settings)
    end

    # After creating a new PR (from reopen), update the issue and enqueue monitor
    def schedule_auto_merge(issue, create_result)
      return unless @project.auto_merge_enabled?
      return unless create_result[:branch_name].to_s.start_with?("ai-fix/")

      status = create_result[:actual_fix_applied] ? "pr_created" : "pr_created_review_needed"
      pr_number = extract_pr_number(create_result[:pr_url])

      issue.update_columns(
        auto_fix_status: status,
        auto_fix_pr_url: create_result[:pr_url],
        auto_fix_pr_number: pr_number,
        auto_fix_branch: create_result[:branch_name],
        auto_fix_attempted_at: Time.current,
        auto_fix_error: nil
      )

      AutoFixMonitorJob.perform_in(10, issue.id, @project.id, 0)
      Rails.logger.info "[PrService] Scheduled AutoFixMonitorJob for issue ##{issue.id} (PR #{create_result[:pr_url]})"
    end

    # For reopened/already-open PRs that have files, schedule monitor if not already running
    def schedule_auto_merge_for_existing_pr(issue, pr_info)
      return unless issue
      return unless @project.auto_merge_enabled?
      return unless pr_info[:head_branch].to_s.start_with?("ai-fix/")
      return if issue.auto_fix_status == "merged"

      unless %w[pr_created pr_created_review_needed ci_pending].include?(issue.auto_fix_status)
        issue.update_columns(
          auto_fix_status: "pr_created",
          auto_fix_pr_url: pr_info[:html_url],
          auto_fix_pr_number: pr_info[:number],
          auto_fix_branch: pr_info[:head_branch],
          auto_fix_attempted_at: Time.current,
          auto_fix_error: nil
        )
      end

      AutoFixMonitorJob.perform_in(10, issue.id, @project.id, 0)
      Rails.logger.info "[PrService] Scheduled AutoFixMonitorJob for reopened PR ##{pr_info[:number]}"
    end

    # Create a commit with actual code fix applied to source files
    def create_fix_commit(api_client, code_fix_applier, owner, repo, branch, base_sha, issue, code_fix, before_code, pr_body, file_fixes = [])
      base_commit = api_client.get("/repos/#{owner}/#{repo}/git/commits/#{base_sha}")
      base_tree_sha = base_commit.is_a?(Hash) ? base_commit["tree"]&.dig("sha") : nil
      return { error: "Failed to read base commit" } unless base_tree_sha

      tree_entries = []
      commit_msg_parts = []
      unapplied_fixes = []

      sample_event = issue.events&.order(occurred_at: :desc)&.first
      actual_fix_applied = false
      files_fixed = []

      # --- Primary file fix (try multiple strategies) ---
      primary_file_path = nil

      if sample_event&.has_structured_stack_trace?
        fix_result = code_fix_applier.try_apply_actual_fix(owner, repo, sample_event, issue, code_fix, before_code)
        if fix_result[:success]
          tree_entries << fix_result[:tree_entry]
          commit_msg_parts << "fix: #{fix_result[:file_path]}"
          files_fixed << fix_result[:file_path]
          actual_fix_applied = true
          primary_file_path = fix_result[:file_path]
          Rails.logger.info "[GitHub API] Applied actual code fix to #{fix_result[:file_path]}"
        else
          Rails.logger.info "[GitHub API] Smart fix failed for primary file: #{fix_result[:reason]}"
          primary_file_path = fix_result[:file_path]
        end
      end

      # When no in-app frame (e.g. ActionNotFound, RoutingError), infer file
      # path from controller_action and attempt an AI-assisted fix directly.
      if !actual_fix_applied && primary_file_path.nil? && issue.controller_action.present?
        inferred_path = infer_file_path_from_controller(issue.controller_action)
        if inferred_path
          Rails.logger.info "[GitHub API] Inferred file path #{inferred_path} from #{issue.controller_action}"
          fix_result = code_fix_applier.try_apply_fix_to_file(owner, repo, inferred_path, before_code, code_fix)
          if fix_result[:success]
            tree_entries << fix_result[:tree_entry]
            commit_msg_parts << "fix: #{fix_result[:file_path]}"
            files_fixed << fix_result[:file_path]
            actual_fix_applied = true
            primary_file_path = fix_result[:file_path]
            Rails.logger.info "[GitHub API] Inferred-path fix succeeded for #{fix_result[:file_path]}"
          else
            primary_file_path = inferred_path
            Rails.logger.info "[GitHub API] Inferred-path fix failed for #{inferred_path}: #{fix_result[:reason]}"
          end
        end
      end

      # Fallback: try simpler try_apply_fix_to_file on the primary file
      if !actual_fix_applied && code_fix.present?
        fallback_path = primary_file_path || file_fixes&.first&.dig(:file_path)
        if fallback_path.present?
          Rails.logger.info "[GitHub API] Trying fallback fix on #{fallback_path}"
          fix_result = code_fix_applier.try_apply_fix_to_file(owner, repo, fallback_path, before_code, code_fix)
          if fix_result[:success]
            tree_entries << fix_result[:tree_entry]
            commit_msg_parts << "fix: #{fix_result[:file_path]}"
            files_fixed << fix_result[:file_path]
            actual_fix_applied = true
            Rails.logger.info "[GitHub API] Fallback fix succeeded for #{fix_result[:file_path]}"
          else
            Rails.logger.info "[GitHub API] Fallback fix also failed for #{fallback_path}: #{fix_result[:reason]}"
            unapplied_fixes << { file_path: fallback_path, before_code: before_code, after_code: code_fix }
          end
        end
      end

      # --- Additional file fixes (multi-file support) ---
      max_files = AiSummaryService::MAX_FILES_PER_FIX

      if file_fixes.present? && file_fixes.size > 1 && files_fixed.size < max_files
        remaining_slots = max_files - files_fixed.size
        additional_fixes = file_fixes.drop(1).first(remaining_slots)

        additional_fixes.each do |file_fix|
          break if files_fixed.size >= max_files
          next if files_fixed.include?(file_fix[:file_path])
          next unless file_fix[:after_code].present?

          fix_result = code_fix_applier.try_apply_fix_to_file(
            owner, repo,
            file_fix[:file_path],
            file_fix[:before_code],
            file_fix[:after_code]
          )

          if fix_result[:success]
            tree_entries << fix_result[:tree_entry]
            commit_msg_parts << "fix: #{fix_result[:file_path]}"
            files_fixed << fix_result[:file_path]
            actual_fix_applied = true
            Rails.logger.info "[GitHub API] Applied additional fix to #{fix_result[:file_path]}"
          else
            Rails.logger.info "[GitHub API] Could not apply fix to #{file_fix[:file_path]}: #{fix_result[:reason]}"
            unapplied_fixes << file_fix
          end
        end
      end

      Rails.logger.info "[GitHub API] Files fixed: #{files_fixed.size} (#{files_fixed.join(', ')}), unapplied: #{unapplied_fixes.size}"

      # Create commit — either with real fixes or an empty commit so the PR has a branch
      if tree_entries.any?
        tree = api_client.post("/repos/#{owner}/#{repo}/git/trees", {
          base_tree: base_tree_sha,
          tree: tree_entries
        })
        new_tree_sha = tree.is_a?(Hash) ? tree["sha"] : nil
        return { error: "Failed to create tree" } unless new_tree_sha

        commit_msg = "fix: #{issue.exception_class} in #{issue.controller_action.to_s.split('#').last}\n\n#{commit_msg_parts.join("\n")}"
      else
        new_tree_sha = base_tree_sha
        commit_msg = "chore: investigate #{issue.exception_class} in #{issue.controller_action.to_s.split('#').last}\n\nAI-suggested fix needs manual review"
      end

      commit = api_client.post("/repos/#{owner}/#{repo}/git/commits", {
        message: commit_msg,
        tree: new_tree_sha,
        parents: [base_sha]
      })
      new_commit_sha = commit.is_a?(Hash) ? commit["sha"] : nil
      return { error: "Failed to create commit" } unless new_commit_sha

      ref_update = api_client.patch("/repos/#{owner}/#{repo}/git/refs/heads/#{branch}", {
        sha: new_commit_sha,
        force: false
      })
      if ref_update.is_a?(Hash) && ref_update[:error]
        return { error: ref_update[:error] }
      end

      Rails.logger.info "[GitHub API] Created commit #{new_commit_sha[0, 7]} on #{branch} (actual_fix: #{actual_fix_applied})"
      { success: true, commit_sha: new_commit_sha, actual_fix_applied: actual_fix_applied, unapplied_fixes: unapplied_fixes }
    end

    def unapplied_fixes_section(unapplied_fixes)
      lines = ["\n\n## 🔧 Additional Fixes (Manual Application Required)\n"]
      lines << "> The following file changes could not be applied automatically. Please apply them manually.\n"

      unapplied_fixes.each_with_index do |fix, idx|
        lines << "### #{idx + 1}. `#{fix[:file_path]}`\n"
        if fix[:before_code].present?
          lines << "**Before:**"
          lines << "```ruby"
          lines << fix[:before_code].strip
          lines << "```\n"
        end
        if fix[:after_code].present?
          lines << "**After:**"
          lines << "```ruby"
          lines << fix[:after_code].strip
          lines << "```\n"
        end
      end

      lines.join("\n")
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
end
