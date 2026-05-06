require "rails_helper"

RSpec.describe Sentry::ImportService do
  let(:account) { create(:account) }
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      create(:project, name: "P", environment: "production",
             settings: {
               "sentry_org_slug" => "acme",
               "sentry_project_slug" => "backend",
               "sentry_auth_token" => "tkn"
             })
    end
  end
  let(:client) { instance_double(Sentry::Client) }
  let(:issues) do
    [
      { sentry_issue_id: "1", title: "ErrA", exception_class: "A", platform: "ruby",
        permalink: "p1", last_seen: nil, event_count: 1, user_count: 1, culprit: "X#a", exception_message: nil, raw: {} },
      { sentry_issue_id: "2", title: "ErrB", exception_class: "B", platform: "ruby",
        permalink: "p2", last_seen: nil, event_count: 2, user_count: 1, culprit: "X#b", exception_message: nil, raw: {} }
    ]
  end

  before do
    allow(Sentry::Client).to receive(:new).with("tkn").and_return(client)
    allow(client).to receive(:list_issues).and_return(issues)
  end

  it "creates one Issue per Sentry issue and stamps initial_import_completed_at" do
    ActsAsTenant.with_tenant(account) do
      expect { described_class.call(project) }.to change { project.issues.count }.by(2)
      expect(project.reload.settings["sentry_initial_import_completed_at"]).to be_present
    end
  end

  it "broadcasts a Turbo Stream row per issue" do
    expect(Turbo::StreamsChannel).to receive(:broadcast_append_to)
      .with("project:#{project.id}:onboarding", hash_including(target: "status_rows"))
      .at_least(:twice)
    ActsAsTenant.with_tenant(account) { described_class.call(project) }
  end
end
