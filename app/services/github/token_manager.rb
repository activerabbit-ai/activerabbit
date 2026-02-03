# frozen_string_literal: true

# Manages GitHub authentication tokens (PAT and App installation tokens)
module Github
  class TokenManager
    def initialize(project_pat:, installation_id:, env_pat:, project_app_id:, project_app_pk:, env_app_id:, env_app_pk:)
      @project_pat = project_pat
      @installation_id = installation_id
      @env_pat = env_pat
      @project_app_id = project_app_id
      @project_app_pk = project_app_pk
      @env_app_id = env_app_id
      @env_app_pk = env_app_pk
    end

    def get_token
      @project_pat.presence || generate_installation_token || @env_pat
    end

    def configured?
      (@project_pat.present? || @installation_id.present? || @env_pat.present?)
    end

    private

    def generate_installation_token
      return nil unless @installation_id.present?
      # Prefer per-project app creds; fallback to env.
      app_id = @project_app_id.presence || @env_app_id
      pk_pem = @project_app_pk.presence || @env_app_pk
      return nil unless app_id.present? && pk_pem.present?

      jwt = generate_app_jwt(app_id, pk_pem)
      resp = http_post_json("https://api.github.com/app/installations/#{@installation_id}/access_tokens", nil, {
        "Authorization" => "Bearer #{jwt}",
        "Accept" => "application/vnd.github+json"
      })
      resp&.dig("token")
    end

    def generate_app_jwt(app_id, pk_pem)
      require "openssl"
      require "jwt"
      private_key = OpenSSL::PKey::RSA.new(pk_pem)
      payload = { iat: Time.now.to_i - 60, exp: Time.now.to_i + (10 * 60), iss: app_id.to_i }
      JWT.encode(payload, private_key, "RS256")
    end

    def http_post_json(url, body, headers)
      require "net/http"
      require "json"
      uri = URI(url)
      req = Net::HTTP::Post.new(uri)
      headers.each { |k, v| req[k] = v }
      req.body = body ? JSON.generate(body) : ""
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
      JSON.parse(res.body) rescue {}
    end
  end
end
