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
      @env_app_pk = load_env_private_key
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

      # Create commit with suggested fix if available
      # Pass source_branch so CodeFixApplier fetches file from correct branch
      code_fix_applier = Github::CodeFixApplier.new(api_client: api_client, anthropic_key: @anthropic_key, source_branch: source_branch)
      commit_result = create_fix_commit(api_client, code_fix_applier, owner, repo, branch, head_sha, issue, code_fix, pr_body)
      if commit_result.is_a?(Hash) && commit_result[:error]
        return { success: false, error: commit_result[:error] }
      end

      # Track if actual fix was applied from commit result
      actual_fix_applied = commit_result.is_a?(Hash) && commit_result[:actual_fix_applied]

      pr = api_client.post("/repos/#{owner}/#{repo}/pulls", {
        title: pr_title,
        head: branch,
        base: base_branch,
        body: pr_body,
        draft: true
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

    # Load private key from environment (supports multiple formats)
    def load_env_private_key
      if ENV["AR_GH_APP_PK_FILE"].present? && File.exist?(ENV["AR_GH_APP_PK_FILE"])
        File.read(ENV["AR_GH_APP_PK_FILE"])
      elsif ENV["AR_GH_APP_PK_BASE64"].present?
        Base64.decode64(ENV["AR_GH_APP_PK_BASE64"])
      elsif ENV["AR_GH_APP_PK"].present?
        ENV["AR_GH_APP_PK"].gsub('\n', "\n")
      end
    end

    # Create a commit with actual code fix or fallback to suggestion file
    def create_fix_commit(api_client, code_fix_applier, owner, repo, branch, base_sha, issue, code_fix, pr_body)
      # Get base commit tree
      base_commit = api_client.get("/repos/#{owner}/#{repo}/git/commits/#{base_sha}")
      base_tree_sha = base_commit.is_a?(Hash) ? base_commit["tree"]&.dig("sha") : nil
      return { error: "Failed to read base commit" } unless base_tree_sha

      tree_entries = []
      commit_msg_parts = []

      # Try to apply actual code fix to the source file
      sample_event = issue.events.order(occurred_at: :desc).first
      actual_fix_applied = false

      if sample_event&.has_structured_stack_trace?
        # Pass the existing AI summary fix code to try_apply_actual_fix
        # This ensures we use the same fix the user saw in the AI Analysis panel
        fix_result = code_fix_applier.try_apply_actual_fix(owner, repo, sample_event, issue, code_fix)
        if fix_result[:success]
          tree_entries << fix_result[:tree_entry]
          commit_msg_parts << "fix: #{fix_result[:file_path]}"
          actual_fix_applied = true
          Rails.logger.info "[GitHub API] Applied actual code fix to #{fix_result[:file_path]}"
        else
          Rails.logger.info "[GitHub API] Could not apply actual fix: #{fix_result[:reason]}"
        end
      end

      # Only add suggestion file if no actual fix was applied
      unless actual_fix_applied
        fix_file_content = build_fix_file_content(issue, code_fix, pr_body, actual_fix_applied)
        blob = api_client.post("/repos/#{owner}/#{repo}/git/blobs", {
          content: fix_file_content,
          encoding: "utf-8"
        })
        blob_sha = blob.is_a?(Hash) ? blob["sha"] : nil
        return { error: "Failed to create blob" } unless blob_sha

        tree_entries << { path: ".activerabbit/fixes/issue-#{issue.id}-fix.md", mode: "100644", type: "blob", sha: blob_sha }
      end

      # Create tree with all entries
      tree = api_client.post("/repos/#{owner}/#{repo}/git/trees", {
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

      commit = api_client.post("/repos/#{owner}/#{repo}/git/commits", {
        message: commit_msg,
        tree: new_tree_sha,
        parents: [base_sha]
      })
      new_commit_sha = commit.is_a?(Hash) ? commit["sha"] : nil
      return { error: "Failed to create commit" } unless new_commit_sha

      # Update branch ref
      ref_update = api_client.patch("/repos/#{owner}/#{repo}/git/refs/heads/#{branch}", {
        sha: new_commit_sha,
        force: false
      })
      if ref_update.is_a?(Hash) && ref_update[:error]
        return { error: ref_update[:error] }
      end

      Rails.logger.info "[GitHub API] Created fix commit #{new_commit_sha[0, 7]} on #{branch} (actual_fix: #{actual_fix_applied})"
      { success: true, commit_sha: new_commit_sha, actual_fix_applied: actual_fix_applied }
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
