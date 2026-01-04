require 'rails_helper'

RSpec.describe User, type: :model do
  it 'auto-creates an account on create' do
    user = build(:user, account: nil)
    expect { user.save! }.to change { Account.count }.by(1)
    expect(user.account).to be_present
  end

  it 'responds to needs_onboarding?' do
    user = create(:user)

    expect(user.needs_onboarding?).to eq(true)

    ActsAsTenant.with_tenant(user.account) do
      create(:project, user: user, account: user.account)
    end

    expect(user.needs_onboarding?).to eq(false)
  end

  describe "roles" do
    let(:account) { create(:account) }

    describe "#owner?" do
      it "returns true for owner role" do
        user = create(:user, account: account, role: "owner")
        expect(user.owner?).to be true
      end

      it "returns false for member role" do
        user = create(:user, account: account, role: "member")
        expect(user.owner?).to be false
      end
    end

    describe "#member?" do
      it "returns true for member role" do
        user = create(:user, account: account, role: "member")
        expect(user.member?).to be true
      end

      it "returns false for owner role" do
        user = create(:user, account: account, role: "owner")
        expect(user.member?).to be false
      end
    end

    describe "default role assignment" do
      it "assigns owner role when not invited" do
        user = create(:user, account: account, invited_by: nil, role: nil)
        expect(user.role).to eq("owner")
      end

      it "assigns member role when invited without explicit role" do
        owner = create(:user, account: account, role: "owner")
        user = create(:user, account: account, invited_by: owner, role: nil)
        expect(user.role).to eq("member")
      end
    end
  end

  describe "project association" do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }

    it "has many projects with dependent nullify" do
      association = described_class.reflect_on_association(:projects)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:nullify)
    end

    it "nullifies project user_id when user is deleted" do
      ActsAsTenant.with_tenant(account) do
        project = create(:project, user: user, account: account)

        user.destroy!

        expect(project.reload.user_id).to be_nil
      end
    end

    it "does not delete projects when user is deleted" do
      ActsAsTenant.with_tenant(account) do
        project = create(:project, user: user, account: account)

        expect { user.destroy! }.not_to change { Project.count }

        expect(project.reload).to be_present
      end
    end
  end

  describe "password requirement" do
    let(:account) { create(:account) }
    let(:owner) { create(:user, account: account, role: "owner") }

    it "requires password when not invited" do
      user = build(:user, account: account, password: nil, invited_by: nil)
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "does not require password when invited" do
      user = build(:user, account: account, password: nil, invited_by: owner)
      expect(user).to be_valid
    end
  end
end
