require "rails_helper"

RSpec.describe "Project Settings — auto-fix", type: :request do
  let(:account) { create(:account) }
  let(:user) do
    u = create(:user)
    account.users << u unless account.users.include?(u)
    u
  end
  let(:project) { ActsAsTenant.with_tenant(account) { create(:project, name: "P", environment: "production") } }

  before do
    login_as(user, scope: :user)
    ActsAsTenant.current_tenant = account
  end

  it "updates weekly cap and confidence" do
    patch project_settings_path(project), params: {
      project: { auto_pr_weekly_cap: 10, auto_pr_confidence_threshold: 60 }
    }
    expect(project.reload.auto_pr_weekly_cap).to eq(10)
    expect(project.auto_pr_confidence_threshold).to eq(60)
  end
end
