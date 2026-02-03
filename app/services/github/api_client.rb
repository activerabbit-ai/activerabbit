# frozen_string_literal: true

module Github
  # GitHub API client for making HTTP requests to GitHub API
  class ApiClient
    def initialize(token)
      @token = token
    end

    def get(path)
      http_json("https://api.github.com#{path}", headers)
    end

    def post(path, body)
      result = http_post_json("https://api.github.com#{path}", body, headers)
      return { error: result[:error] } if result.is_a?(Hash) && result[:error]
      result
    end

    def patch(path, body)
      result = http_patch_json("https://api.github.com#{path}", body, headers)
      return { error: result[:error] } if result.is_a?(Hash) && result[:error]
      result
    end

    def detect_default_branch(owner, repo)
      repo_json = get("/repos/#{owner}/#{repo}")
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

    private

    def headers
      { "Authorization" => "Bearer #{@token}", "Accept" => "application/vnd.github+json" }
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
  end
end
