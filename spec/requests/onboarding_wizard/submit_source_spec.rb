require "rails_helper"

RSpec.describe "OnboardingWizard#submit_source", type: :request do
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

  it "with preview=sentry returns turbo stream replacing sentry_card" do
    post "/onboarding/source", params: { preview: "sentry" },
                               headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response.body).to include("turbo-stream")
    expect(response.body).to include("step_1_sentry_form").or include("Sentry auth token")
  end

  it "with source=sdk creates Project and redirects to /onboarding (Step 2)" do
    expect {
      post "/onboarding/source", params: { source: "sdk", app_name: "my-app" }
    }.to change { ActsAsTenant.with_tenant(account) { Project.count } }.by(1)
    expect(response).to redirect_to(onboarding_path)
    project = ActsAsTenant.with_tenant(account) { Project.last }
    expect(project.name).to eq("my-app")
  end
end
