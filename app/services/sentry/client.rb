module Sentry
  class Client
    BASE = "https://sentry.io/api/0".freeze

    def initialize(token)
      @token = token
    end

    def verify_token
      get("/").is_a?(Hash) && @last_status == 200
    end

    def list_projects
      response = get("/projects/")
      return [] unless @last_status == 200
      Array(response).map do |p|
        {
          org_slug: p.dig("organization", "slug"),
          project_slug: p["slug"],
          name: p["name"],
          platform: p["platform"]
        }
      end
    end

    def list_issues(org:, project_slug:, days: 7, limit: 100)
      response = get(
        "/projects/#{org}/#{project_slug}/issues/",
        query: { "statsPeriod" => "#{days}d", "limit" => limit.to_s, "query" => "is:unresolved" }
      )
      return [] unless @last_status == 200
      Array(response).map do |i|
        {
          sentry_issue_id: i["id"],
          title: i["title"],
          culprit: i["culprit"],
          exception_class: i.dig("metadata", "type"),
          exception_message: i.dig("metadata", "value"),
          permalink: i["permalink"],
          platform: i["platform"],
          last_seen: i["lastSeen"],
          event_count: i["count"].to_i,
          user_count: i["userCount"].to_i,
          raw: i
        }
      end
    end

    def register_internal_integration(org:, webhook_url:, name:)
      app = post("/organizations/#{org}/sentry-apps/", body: {
        name: name,
        webhookUrl: webhook_url,
        scopes: %w[event:read project:read],
        events: %w[issue],
        isInternal: true
      })
      return { error: "create_failed" } unless @last_status.between?(200, 299) && app["slug"]
      tok = post("/sentry-apps/#{app['slug']}/api-tokens/", body: {})
      { integration_uuid: app["uuid"], integration_slug: app["slug"], api_token: tok["token"] }
    end

    private

    def get(path, query: {})
      require "net/http"
      require "json"
      uri = URI("#{BASE}#{path}")
      uri.query = URI.encode_www_form(query) if query.any?
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{@token}"
      req["Accept"] = "application/json"
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
      @last_status = res.code.to_i
      JSON.parse(res.body) rescue {}
    end

    def post(path, body:)
      require "net/http"
      require "json"
      uri = URI("#{BASE}#{path}")
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{@token}"
      req["Accept"] = "application/json"
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body)
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |h| h.request(req) }
      @last_status = res.code.to_i
      JSON.parse(res.body) rescue {}
    end
  end
end
