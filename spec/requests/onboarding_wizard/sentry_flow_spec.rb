require "rails_helper"

RSpec.describe "OnboardingWizard sentry flow", type: :request do
  let(:account) { create(:account) }
  let(:user) do
    u = create(:user)
    account.users << u unless account.users.include?(u)
    u
  end

  before do
    login_as(user, scope: :user)
    ActsAsTenant.current_tenant = account
  end

  describe "POST /onboarding/sentry/verify" do
    it "shows project picker on valid token" do
      client = instance_double(Sentry::Client)
      allow(Sentry::Client).to receive(:new).with("tkn").and_return(client)
      allow(client).to receive(:verify_token).and_return(true)
      allow(client).to receive(:list_projects).and_return([
        { org_slug: "acme", project_slug: "backend", name: "Backend", platform: "ruby" }
      ])
      post "/onboarding/sentry/verify", params: { token: "tkn", app_name: "" }
      expect(response.body).to include("Backend")
    end

    it "shows inline error on invalid token" do
      allow_any_instance_of(Sentry::Client).to receive(:verify_token).and_return(false)
      post "/onboarding/sentry/verify", params: { token: "bad" }
      expect(response.body).to include("Invalid token")
    end
  end

  describe "POST /onboarding/sentry/import" do
    it "creates Project, enqueues import, advances wizard" do
      ActiveJob::Base.queue_adapter = :test
      expect {
        post "/onboarding/sentry/import",
             params: { app_name: "Backend", token: "tkn",
                       org_slug: "acme", project_slug: "backend", platform: "ruby" }
      }.to change { ActsAsTenant.with_tenant(account) { Project.count } }.by(1)
        .and have_enqueued_job(Sentry::ImportProjectJob)
      expect(response).to redirect_to(onboarding_path)
    end
  end
end
