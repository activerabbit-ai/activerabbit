# frozen_string_literal: true

module Github
  # Generates branch names for GitHub PRs
  class BranchNameGenerator
    include AiProviderChat

    def initialize(account:)
      @account = account
    end

    def generate(issue, custom_branch_name = nil)
      # If user provided a custom branch name, sanitize and use it
      if custom_branch_name.present?
        sanitized = sanitize_branch_name(custom_branch_name)
        Rails.logger.info "[GitHub API] Using custom branch name: #{sanitized}"
        return sanitized
      end

      # Try to generate a meaningful branch name using AI
      chat = ai_chat(@account)
      if chat
        ai_branch = generate_ai_branch_name(chat, issue)
        if ai_branch.present?
          Rails.logger.info "[GitHub API] Using AI-generated branch name: #{ai_branch}"
          return ai_branch
        end
      end

      # Fallback to programmatic generation
      fallback_branch = generate_fallback_branch_name(issue)
      Rails.logger.info "[GitHub API] Using fallback branch name: #{fallback_branch}"
      fallback_branch
    end

    private

    def sanitize_branch_name(name)
      # Remove or replace invalid characters for git branch names
      sanitized = name.to_s
        .strip
        .gsub(/[^a-zA-Z0-9\-_\/]/, "-")  # Replace invalid chars with dash
        .gsub(/-+/, "-")                   # Collapse multiple dashes
        .gsub(/^-|-$/, "")                 # Remove leading/trailing dashes
        .downcase

      # Ensure it starts with ai-fix/ if not already
      unless sanitized.start_with?("ai-fix/") || sanitized.start_with?("fix/") || sanitized.include?("/")
        sanitized = "ai-fix/#{sanitized}"
      end

      # Limit length (git has practical limits)
      if sanitized.length > 100
        sanitized = sanitized[0, 100].sub(/-$/, "")
      end

      sanitized
    end

    def generate_ai_branch_name(chat, issue)
      prompt = <<~PROMPT
        Generate a short, descriptive git branch name for fixing this error.

        Error: #{issue.exception_class}
        Message: #{issue.sample_message.to_s[0, 200]}
        Location: #{issue.controller_action}

        Rules:
        - Start with "ai-fix/"
        - Use lowercase letters, numbers, and hyphens only
        - Maximum 50 characters total
        - Be descriptive but concise
        - No spaces or special characters

        Examples:
        - ai-fix/nil-user-profile
        - ai-fix/missing-auth-token
        - ai-fix/invalid-date-format

        Return ONLY the branch name, nothing else.
      PROMPT

      begin
        response = chat.ask(prompt)
        return nil if response.content.blank?

        # Clean up the response
        branch = response.content.strip
          .gsub(/^["']|["']$/, "")  # Remove quotes
          .gsub(/\s+/, "-")          # Replace spaces with dashes
          .downcase

        # Validate format
        return nil unless branch.match?(/^ai-fix\/[a-z0-9\-]+$/)
        return nil if branch.length > 60

        branch
      rescue => e
        Rails.logger.error "[GitHub API] AI branch name generation failed: #{e.message}"
        nil
      end
    end

    def generate_fallback_branch_name(issue)
      # Generate a meaningful name programmatically
      exception_part = issue.exception_class.to_s
        .gsub(/Error$/, "")
        .gsub(/Exception$/, "")
        .gsub(/([a-z])([A-Z])/, '\1-\2')  # CamelCase to kebab-case
        .downcase
        .gsub(/[^a-z0-9]/, "-")
        .gsub(/-+/, "-")
        .gsub(/^-|-$/, "")

      action_part = issue.controller_action.to_s
        .split("#").last.to_s
        .gsub(/[^a-z0-9]/i, "-")
        .downcase
        .gsub(/-+/, "-")
        .gsub(/^-|-$/, "")

      # Combine parts
      if action_part.present? && exception_part.present?
        branch = "ai-fix/#{exception_part}-in-#{action_part}"
      elsif exception_part.present?
        branch = "ai-fix/#{exception_part}"
      else
        branch = "ai-fix/issue-#{issue.id}"
      end

      # Limit length and add unique suffix if needed
      if branch.length > 80
        branch = branch[0, 80].sub(/-$/, "")
      end

      # Add short timestamp to ensure uniqueness
      "#{branch}-#{Time.now.strftime('%m%d%H%M')}"
    end

  end
end
