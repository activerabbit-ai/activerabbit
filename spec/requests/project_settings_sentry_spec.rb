require "rails_helper"

RSpec.describe "Project Settings — sentry", type: :request do
  let(:account) { create(:account) }
  let(:user) do
    u = create(:user)
    account.users << u unless account.users.include?(u)
    u
  end
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      create(:project, name: "P", environment: "production",
             settings: { "sentry_org_slug" => "acme",
                         "sentry_project_slug" => "backend",
                         "sentry_auth_token" => "tkn",
                         "sentry_webhook_secret" => "secret",
                         "sentry_initial_import_completed_at" => Time.current.iso8601,
                         "sentry_internal_integration_uuid" => "uuid",
                         "sentry_internal_integration_token" => "internal" })
    end
  end

  before do
    login_as(user, scope: :user)
    ActsAsTenant.current_tenant = account
  end

  it "disconnects Sentry — strips all sentry_* settings" do
    delete disconnect_sentry_project_settings_path(project)
    settings = project.reload.settings
    expect(settings).not_to include("sentry_org_slug")
    expect(settings).not_to include("sentry_auth_token")
    expect(settings).not_to include("sentry_webhook_secret")
    expect(settings).not_to include("sentry_internal_integration_uuid")
  end

  it "re-imports — enqueues ImportProjectJob" do
    expect {
      post reimport_sentry_project_settings_path(project)
    }.to have_enqueued_job(Sentry::ImportProjectJob).with(project.id)
  end
end
