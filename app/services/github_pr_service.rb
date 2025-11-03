class GithubPrService
  def initialize(project)
    @project = project
    settings = @project.settings || {}
    @github_repo = settings['github_repo'] # e.g., "owner/repo"
    @base_branch_override = settings['github_base_branch']
    # Token precedence: per-project PAT > installation token > env PAT
    @project_pat = settings['github_pat']
    @installation_id = settings['github_installation_id']
    @env_pat = ENV['GITHUB_TOKEN']
    # App creds precedence: per-project > env
    @project_app_id = settings['github_app_id']
    @project_app_pk = settings['github_app_pk']
    @env_app_id = ENV['AR_GH_APP_ID']
    @env_app_pk = ENV['AR_GH_APP_PK']
  end

  def create_n_plus_one_fix_pr(sql_fingerprint)
    return { success: false, error: 'GitHub integration not configured' } unless configured?

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
  public def create_pr_for_issue(issue)
    return { success: false, error: 'GitHub integration not configured' } unless configured?

    owner, repo = @github_repo.split('/', 2)

    token = @project_pat.presence || generate_installation_token(@installation_id) || @env_pat
    return { success: false, error: 'Failed to acquire GitHub token' } unless token.present?

    base_branch = @base_branch_override.presence || detect_default_branch(owner, repo, token) || 'main'
    Rails.logger.info "[GitHub API] Using base_branch=#{base_branch} for #{owner}/#{repo}"

    # Git refs endpoint uses 'refs' (plural)
    head_sha = github_get("/repos/#{owner}/#{repo}/git/refs/heads/#{base_branch}", token)&.dig('object', 'sha')
    return { success: false, error: 'Base branch not found' } unless head_sha

    branch = "ar/fix-issue-#{issue.id}-#{Time.now.to_i}"
    Rails.logger.info "[GitHub API] Creating branch #{branch} from sha=#{head_sha[0, 7]}"
    ref_resp = github_post("/repos/#{owner}/#{repo}/git/refs", token, {
      ref: "refs/heads/#{branch}",
      sha: head_sha
    })
    return { success: false, error: ref_resp[:error] } if ref_resp.is_a?(Hash) && ref_resp[:error]

    pr_body = build_pr_body(issue)

    # Ensure the branch has at least one commit difference so PR can be created
    ensure_commit_resp = ensure_branch_has_changes(owner, repo, token, branch, head_sha, pr_body)
    if ensure_commit_resp.is_a?(Hash) && ensure_commit_resp[:error]
      return { success: false, error: ensure_commit_resp[:error] }
    end

    pr = github_post("/repos/#{owner}/#{repo}/pulls", token, {
      title: "Fix #{issue.exception_class} (Issue ##{issue.id})",
      head: branch,
      base: base_branch,
      body: pr_body,
      draft: true
    })

    if pr.is_a?(Hash) && pr['html_url']
      Rails.logger.info "[GitHub API] PR created url=#{pr['html_url']}"
      { success: true, pr_url: pr['html_url'], branch_name: branch }
    else
      { success: false, error: pr[:error] || 'Unknown PR error' }
    end
  rescue => e
    Rails.logger.error "GitHub PR creation failed: #{e.class}: #{e.message}"
    { success: false, error: e.message }
  end

  def build_pr_body(issue)
    lines = []
    lines << '### Root Cause Analysis'
    lines << (issue.ai_summary.presence || 'Automated RCA will be added.')
    lines << "\n### Reproduction"
    sample = issue.sample_message.present? ? issue.sample_message : 'See stack trace in app.'
    lines << sample
    lines << "\n### Tests"
    lines << '- [ ] Add/verify tests reproducing the error and the fix'
    lines.join("\n\n")
  end

  def generate_installation_token(installation_id)
    return nil unless installation_id.present?
    # Prefer per-project app creds; fallback to env.
    app_id = @project_app_id.presence || @env_app_id
    pk_pem = @project_app_pk.presence || @env_app_pk
    return nil unless app_id.present? && pk_pem.present?

    jwt = generate_app_jwt(app_id, pk_pem)
    resp = http_post_json("https://api.github.com/app/installations/#{installation_id}/access_tokens", nil, { 'Authorization' => "Bearer #{jwt}", 'Accept' => 'application/vnd.github+json' })
    resp&.dig('token')
  end

  def generate_app_jwt(app_id, pk_pem)
    require 'openssl'
    require 'jwt'
    private_key = OpenSSL::PKey::RSA.new(pk_pem)
    payload = { iat: Time.now.to_i - 60, exp: Time.now.to_i + (10 * 60), iss: app_id.to_i }
    JWT.encode(payload, private_key, 'RS256')
  end

  def github_get(path, token)
    http_json("https://api.github.com#{path}", { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/vnd.github+json' })
  end

  def github_post(path, token, body)
    http_post_json("https://api.github.com#{path}", body, { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/vnd.github+json' })
  end

  def github_patch(path, token, body)
    http_patch_json("https://api.github.com#{path}", body, { 'Authorization' => "Bearer #{token}", 'Accept' => 'application/vnd.github+json' })
  end

  def detect_default_branch(owner, repo, token)
    repo_json = github_get("/repos/#{owner}/#{repo}", token)
    default_branch = repo_json.is_a?(Hash) ? repo_json['default_branch'] : nil
    Rails.logger.info "[GitHub API] default_branch=#{default_branch.inspect} for #{owner}/#{repo}"
    default_branch
  rescue
    nil
  end

  def http_json(url, headers)
    require 'net/http'
    require 'json'
    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    headers.each { |k, v| req[k] = v }
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    Rails.logger.info "[GitHub API] GET #{uri.path} status=#{res.code}"
    JSON.parse(res.body)
  end

  def http_post_json(url, body, headers)
    require 'net/http'
    require 'json'
    uri = URI(url)
    req = Net::HTTP::Post.new(uri)
    headers.each { |k, v| req[k] = v }
    req.body = body ? JSON.generate(body) : ''
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    Rails.logger.info "[GitHub API] POST #{uri.path} status=#{res.code}"
    return { error: "HTTP #{res.code}" } if res.code.to_i >= 400
    JSON.parse(res.body) rescue {}
  end

  def http_patch_json(url, body, headers)
    require 'net/http'
    require 'json'
    uri = URI(url)
    req = Net::HTTP::Patch.new(uri)
    headers.each { |k, v| req[k] = v }
    req.body = body ? JSON.generate(body) : ''
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    Rails.logger.info "[GitHub API] PATCH #{uri.path} status=#{res.code}"
    return { error: "HTTP #{res.code}" } if res.code.to_i >= 400
    JSON.parse(res.body) rescue {}
  end

  # Create a placeholder commit on the new branch if it has no changes yet
  def ensure_branch_has_changes(owner, repo, token, branch, base_commit_sha, pr_body)
    # 1) Get base commit to fetch its tree
    base_commit = github_get("/repos/#{owner}/#{repo}/git/commits/#{base_commit_sha}", token)
    base_tree_sha = base_commit.is_a?(Hash) ? base_commit['tree']&.dig('sha') : nil
    return { error: 'Failed to read base commit' } unless base_tree_sha

    # 2) Create a blob with PR context
    content = "Automated PR context from ActiveRabbit\n\n" + pr_body.to_s
    blob = github_post("/repos/#{owner}/#{repo}/git/blobs", token, { content: content, encoding: 'utf-8' })
    blob_sha = blob.is_a?(Hash) ? blob['sha'] : nil
    return { error: 'Failed to create blob' } unless blob_sha

    # 3) Create a tree including the new file
    path = 'activerabbit/AR_PR_CONTEXT.md'
    tree = github_post("/repos/#{owner}/#{repo}/git/trees", token, {
      base_tree: base_tree_sha,
      tree: [
        { path: path, mode: '100644', type: 'blob', sha: blob_sha }
      ]
    })
    new_tree_sha = tree.is_a?(Hash) ? tree['sha'] : nil
    return { error: 'Failed to create tree' } unless new_tree_sha

    # 4) Create a commit
    commit = github_post("/repos/#{owner}/#{repo}/git/commits", token, {
      message: 'chore: add PR context file for automated PR',
      tree: new_tree_sha,
      parents: [base_commit_sha]
    })
    new_commit_sha = commit.is_a?(Hash) ? commit['sha'] : nil
    return { error: 'Failed to create commit' } unless new_commit_sha

    # 5) Move the branch ref to the new commit
    ref_update = github_patch("/repos/#{owner}/#{repo}/git/refs/heads/#{branch}", token, {
      sha: new_commit_sha,
      force: false
    })
    if ref_update.is_a?(Hash) && ref_update[:error]
      return { error: ref_update[:error] }
    end

    Rails.logger.info "[GitHub API] Added placeholder commit #{new_commit_sha[0, 7]} to #{branch}"
    true
  end

  def generate_optimization_suggestions(sql_fingerprint)
    query = sql_fingerprint.normalized_query
    controller_action = sql_fingerprint.controller_action

    suggestions = []

    # Detect common N+1 patterns and suggest fixes
    if query.include?('SELECT') && controller_action
      if query.match?(/users.*id = \?/i)
        suggestions << {
          type: 'eager_loading',
          suggestion: "Consider adding `includes(:user)` to your query in #{controller_action}",
          code_example: "# Instead of:\n# @records.each { |r| r.user.name }\n\n# Use:\n# @records = @records.includes(:user)\n# @records.each { |r| r.user.name }"
        }
      end

      if query.match?(/SELECT.*FROM.*WHERE.*id = \?/i)
        suggestions << {
          type: 'batch_loading',
          suggestion: 'Consider using `preload` or `includes` to batch load associations',
          code_example: "# Use eager loading to reduce database queries:\n# Model.includes(:association).where(...)"
        }
      end
    end

    # Add indexing suggestions
    if sql_fingerprint.avg_duration_ms > 100
      suggestions << {
        type: 'indexing',
        suggestion: 'Consider adding database indexes to improve query performance',
        code_example: "# Add migration:\n# add_index :table_name, :column_name"
      }
    end

    suggestions
  end

  # Mock GitHub API integration methods
  # In a real implementation, these would use the GitHub API

  def create_branch(branch_name)
    # GitHub API: POST /repos/:owner/:repo/git/refs
    true
  end

  def create_file(branch_name, file_path, content, message)
    # GitHub API: PUT /repos/:owner/:repo/contents/:path
    true
  end

  def create_pull_request(branch_name, title, body)
    # GitHub API: POST /repos/:owner/:repo/pulls
    {
      html_url: "https://github.com/#{@github_repo}/pull/123",
      number: 123
    }
  end
end
