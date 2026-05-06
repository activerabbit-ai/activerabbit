require "rails_helper"

RSpec.describe Sentry::Client do
  let(:token) { "sntrys_eyXXXXXX" }
  subject(:client) { described_class.new(token) }

  describe "#verify_token" do
    it "returns true for 200 from /api/0/" do
      stub_request(:get, "https://sentry.io/api/0/")
        .with(headers: { "Authorization" => "Bearer #{token}" })
        .to_return(status: 200, body: "{}")
      expect(client.verify_token).to eq(true)
    end

    it "returns false for 401" do
      stub_request(:get, "https://sentry.io/api/0/")
        .to_return(status: 401, body: '{"detail":"Invalid token"}')
      expect(client.verify_token).to eq(false)
    end
  end

  describe "#list_projects" do
    it "returns project list across all orgs" do
      stub_request(:get, "https://sentry.io/api/0/projects/")
        .to_return(
          status: 200,
          body: JSON.dump([
            { "slug" => "backend", "name" => "Backend",
              "organization" => { "slug" => "acme" }, "platform" => "ruby" },
            { "slug" => "web", "name" => "Web",
              "organization" => { "slug" => "acme" }, "platform" => "javascript" }
          ])
        )
      result = client.list_projects
      expect(result.size).to eq(2)
      expect(result.first).to include(org_slug: "acme", project_slug: "backend", name: "Backend", platform: "ruby")
    end

    it "returns [] on 401" do
      stub_request(:get, "https://sentry.io/api/0/projects/").to_return(status: 401)
      expect(client.list_projects).to eq([])
    end
  end

  describe "#list_issues" do
    it "fetches recent issues with statsPeriod and limit" do
      stub_request(:get, "https://sentry.io/api/0/projects/acme/backend/issues/")
        .with(query: hash_including({ "statsPeriod" => "7d", "limit" => "100", "query" => "is:unresolved" }))
        .to_return(
          status: 200,
          body: JSON.dump([
            { "id" => "1", "title" => "NoMethodError", "culprit" => "X#y",
              "metadata" => { "type" => "NoMethodError", "value" => "undefined method `foo'" },
              "permalink" => "https://sentry.io/issue/1",
              "platform" => "ruby", "lastSeen" => "2026-05-01T00:00:00Z",
              "count" => "12", "userCount" => 3 }
          ])
        )
      issues = client.list_issues(org: "acme", project_slug: "backend", days: 7, limit: 100)
      expect(issues.size).to eq(1)
      expect(issues.first[:sentry_issue_id]).to eq("1")
      expect(issues.first[:title]).to eq("NoMethodError")
    end
  end
end
