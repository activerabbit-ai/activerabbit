require "rails_helper"

RSpec.describe "GitHub callback reconciler", type: :request do
  let(:account) { create(:account) }
  let(:project) { ActsAsTenant.with_tenant(account) { create(:project, name: "P", environment: "production") } }
  let!(:issue)  { ActsAsTenant.with_tenant(account) { create(:issue, project: project, fingerprint: "fp-skip", auto_fix_status: "skipped_no_github") } }
  let(:user) do
    u = create(:user)
    account.users << u unless account.users.include?(u)
    u
  end

  before do
    allow_any_instance_of(Github::InstallationService).to receive(:fetch_installation_info)
      .and_return(success: true, repository: "acme/p", default_branch: "main")
    login_as(user, scope: :user)
    ActsAsTenant.current_tenant = account
  end

  it "resets skipped_no_github issues to nil and re-enqueues AutoFixJob" do
    expect(AutoFixJob).to receive(:perform_async).with(issue.id, project.id)
    get "/github/app/callback", params: { installation_id: "12345", state: project.id }
    expect(issue.reload.auto_fix_status).to be_nil
  end
end
