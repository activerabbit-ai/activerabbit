require "rails_helper"

RSpec.describe "Sentry webhook", type: :request do
  let(:account) { create(:account) }
  let(:secret)  { "supersecret" }
  let(:project) do
    ActsAsTenant.with_tenant(account) do
      create(:project, name: "P", environment: "production",
             settings: { "sentry_webhook_secret" => secret,
                         "sentry_org_slug" => "acme",
                         "sentry_project_slug" => "backend" })
    end
  end
  let(:body) { JSON.dump({ "data" => { "issue" => { "id" => "99", "title" => "Boom" } } }) }
  let(:sig)  { OpenSSL::HMAC.hexdigest("SHA256", secret, body) }

  it "rejects when signature missing" do
    post "/webhooks/sentry/#{project.id}", params: body, headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects when signature mismatched" do
    post "/webhooks/sentry/#{project.id}", params: body,
         headers: { "Content-Type" => "application/json", "Sentry-Hook-Signature" => "deadbeef" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "accepts valid signature and enqueues IngestEventJob" do
    expect {
      post "/webhooks/sentry/#{project.id}", params: body,
           headers: { "Content-Type" => "application/json", "Sentry-Hook-Signature" => sig }
    }.to have_enqueued_job(Sentry::IngestEventJob)
    expect(response).to have_http_status(:ok)
  end
end
