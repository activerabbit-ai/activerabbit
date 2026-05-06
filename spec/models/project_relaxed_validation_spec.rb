require "rails_helper"

RSpec.describe Project, type: :model do
  describe "create-time validations" do
    let(:account) { Account.create!(name: "Acme") }

    it "creates without url or tech_stack" do
      ActsAsTenant.with_tenant(account) do
        p = Project.new(name: "X", environment: "production")
        expect(p.save).to be true
      end
    end

    it "still requires name" do
      ActsAsTenant.with_tenant(account) do
        p = Project.new(environment: "production")
        expect(p.save).to be false
        expect(p.errors[:name]).to be_present
      end
    end
  end
end
