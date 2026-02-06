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
    let(:account) { @test_account }

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

    describe "#super_admin?" do
      it "returns true when super_admin is true" do
        user = create(:user, account: account, super_admin: true)
        expect(user.super_admin?).to be true
      end

      it "returns false when super_admin is false" do
        user = create(:user, account: account, super_admin: false)
        expect(user.super_admin?).to be false
      end

      it "defaults to false" do
        user = create(:user, account: account)
        expect(user.super_admin?).to be false
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
    let(:account) { @test_account }
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
    let(:account) { @test_account }
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

  describe "#email_confirmed?" do
    let(:account) { @test_account }

    context "when user has confirmed_at set" do
      it "returns true" do
        user = create(:user, :confirmed, account: account)
        expect(user.email_confirmed?).to be true
      end
    end

    context "when user has not confirmed email" do
      it "returns false" do
        user = create(:user, :unconfirmed, account: account)
        expect(user.email_confirmed?).to be false
      end
    end

    context "when user signed up via OAuth" do
      it "returns true even without confirmed_at" do
        user = create(:user, :oauth, account: account)
        expect(user.confirmed_at).to be_nil
        expect(user.provider).to be_present
        expect(user.email_confirmed?).to be true
      end
    end

    context "when user has both provider and confirmed_at" do
      it "returns true" do
        user = create(:user, account: account, provider: "github", confirmed_at: Time.current)
        expect(user.email_confirmed?).to be true
      end
    end
  end

  describe ".from_omniauth" do
    let(:account) { @test_account }

    let(:auth) do
      OmniAuth::AuthHash.new(
        provider: "github",
        uid: "12345",
        info: { email: "oauth@example.com", name: "OAuth User" }
      )
    end

    context "when creating a new OAuth user" do
      it "auto-confirms the user" do
        user = User.from_omniauth(auth)

        expect(user.provider).to eq("github")
        expect(user.confirmed_at).to be_present
        expect(user.email_confirmed?).to be true
      end
    end

    context "when existing OAuth user logs in again" do
      let!(:existing_user) do
        user = build(:user, account: account, provider: "github", uid: "12345", email: "oauth@example.com", confirmed_at: nil)
        user.skip_confirmation_notification!
        user.save!
        user
      end

      it "auto-confirms the user if not confirmed" do
        expect(existing_user.confirmed_at).to be_nil

        user = User.from_omniauth(auth)

        expect(user.id).to eq(existing_user.id)
        expect(user.reload.confirmed_at).to be_present
      end
    end

    context "when existing email user links OAuth" do
      let!(:existing_user) do
        create(:user, :unconfirmed, account: account, email: "oauth@example.com")
      end

      it "links OAuth and auto-confirms the user" do
        expect(existing_user.provider).to be_nil
        expect(existing_user.confirmed_at).to be_nil

        user = User.from_omniauth(auth)

        expect(user.id).to eq(existing_user.id)
        expect(user.reload.provider).to eq("github")
        expect(user.confirmed_at).to be_present
      end
    end
  end
end
