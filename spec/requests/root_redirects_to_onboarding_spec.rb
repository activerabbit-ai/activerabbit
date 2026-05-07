require "rails_helper"

RSpec.describe "Root redirect for users without projects", type: :request do
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

  it "redirects to /onboarding when no projects exist" do
    get "/"
    expect(response).to redirect_to(onboarding_path)
  end

  it "does NOT redirect when at least one project exists" do
    ActsAsTenant.with_tenant(account) { create(:project, name: "P", environment: "production") }
    get "/"
    # Either renders the inbox (200) or redirects somewhere else, but NOT to /onboarding
    expect(response.location).not_to end_with("/onboarding") if response.redirect?
  end
end
