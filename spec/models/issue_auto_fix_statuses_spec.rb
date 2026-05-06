require "rails_helper"

RSpec.describe Issue, "auto_fix_status enum" do
  let(:account) { create(:account) }
  let(:project) { ActsAsTenant.with_tenant(account) { create(:project, name: "P", environment: "production") } }

  %w[skipped_low_confidence skipped_capped skipped_no_github skipped_no_analysis].each do |val|
    it "accepts #{val}" do
      ActsAsTenant.with_tenant(account) do
        issue = build(:issue, project: project, fingerprint: "fp-#{val}", auto_fix_status: val)
        expect(issue).to be_valid
      end
    end
  end
end
