require "rails_helper"

RSpec.describe "OnboardingWizard#show", type: :request do
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

  it "renders Step 1 when no project exists" do
    get "/onboarding"
    expect(response.body).to include("step-1")
  end

  it "renders Step 2 when project exists but github not installed" do
    ActsAsTenant.with_tenant(account) { create(:project, name: "P", environment: "production") }
    get "/onboarding"
    expect(response.body).to include("step-2")
  end

  it "renders Step 3 when project exists and github_installation_id is set" do
    ActsAsTenant.with_tenant(account) do
      create(:project, name: "P", environment: "production",
             settings: { "github_installation_id" => "1" })
    end
    get "/onboarding"
    expect(response.body).to include("step-3")
  end
end
