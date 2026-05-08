require "rails_helper"

RSpec.describe Sentry::EventMapper do
  let(:account) { create(:account) }
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      create(:project, account: account,
                       environment: "production",
                       settings: { "sentry_org_slug" => "acme", "sentry_project_slug" => "backend" })
    end
  end
  let(:payload) do
    {
      sentry_issue_id: "42",
      title: "NoMethodError: undefined method `foo'",
      culprit: "UsersController#show",
      exception_class: "NoMethodError",
      exception_message: "undefined method `foo'",
      permalink: "https://sentry.io/issue/42",
      platform: "ruby",
      last_seen: "2026-05-05T10:00:00Z",
      event_count: 7,
      user_count: 2,
      raw: {}
    }
  end

  it "creates an Issue keyed on a stable fingerprint" do
    ActsAsTenant.with_tenant(account) do
      issue = described_class.upsert!(project, payload)
      expect(issue).to be_persisted
      expect(issue.fingerprint).to eq("sentry:42")
      expect(issue.exception_class).to eq("NoMethodError")
    end
  end

  it "is idempotent — second call updates the same row" do
    ActsAsTenant.with_tenant(account) do
      a = described_class.upsert!(project, payload)
      b = described_class.upsert!(project, payload.merge(event_count: 9))
      expect(a.id).to eq(b.id)
    end
  end
end
