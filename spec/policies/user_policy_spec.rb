require 'rails_helper'

RSpec.describe UserPolicy, type: :policy do
  let(:account) { @test_account }

  describe "permitted_attributes" do
    context "when user is owner" do
      let(:owner) { create(:user, account: account, role: "owner", super_admin: false) }

      context "editing themselves" do
        it "permits profile fields" do
          policy = UserPolicy.new(owner, owner)
          expect(policy.permitted_attributes).to contain_exactly(
            :email, :password, :password_confirmation, :current_password
          )
        end

        it "does not permit super_admin even for own profile" do
          policy = UserPolicy.new(owner, owner)
          expect(policy.permitted_attributes).not_to include(:super_admin)
        end
      end

      context "editing another user" do
        let(:other_user) { create(:user, account: account, role: "member") }

        it "permits email and role" do
          policy = UserPolicy.new(owner, other_user)
          expect(policy.permitted_attributes).to contain_exactly(:email, :role)
        end

        it "does not permit super_admin" do
          policy = UserPolicy.new(owner, other_user)
          expect(policy.permitted_attributes).not_to include(:super_admin)
        end
      end
    end

    context "when user is super_admin" do
      let(:super_admin) { create(:user, account: account, role: "owner", super_admin: true) }

      context "editing themselves" do
        it "permits profile fields but not super_admin" do
          policy = UserPolicy.new(super_admin, super_admin)
          expect(policy.permitted_attributes).to contain_exactly(
            :email, :password, :password_confirmation, :current_password
          )
          expect(policy.permitted_attributes).not_to include(:super_admin)
        end
      end

      context "editing another user" do
        let(:other_user) { create(:user, account: account, role: "member", super_admin: false) }

        it "permits email, role, and super_admin" do
          policy = UserPolicy.new(super_admin, other_user)
          expect(policy.permitted_attributes).to contain_exactly(:email, :role, :super_admin)
        end
      end
    end

    context "when user is member" do
      let(:member) { create(:user, account: account, role: "member") }

      context "editing themselves" do
        it "permits profile fields" do
          policy = UserPolicy.new(member, member)
          expect(policy.permitted_attributes).to contain_exactly(
            :email, :password, :password_confirmation, :current_password
          )
        end
      end

      context "editing another user" do
        let(:other_user) { create(:user, account: account, role: "member") }

        it "returns empty array" do
          policy = UserPolicy.new(member, other_user)
          expect(policy.permitted_attributes).to be_empty
        end
      end
    end
  end

  describe "authorization" do
    let(:owner) { create(:user, account: account, role: "owner") }
    let(:member) { create(:user, account: account, role: "member") }
    let(:other_member) { create(:user, account: account, role: "member") }

    describe "#index?" do
      it "allows owner" do
        expect(UserPolicy.new(owner, User).index?).to be true
      end

      it "denies member" do
        expect(UserPolicy.new(member, User).index?).to be false
      end
    end

    describe "#create?" do
      it "allows owner" do
        expect(UserPolicy.new(owner, User.new).create?).to be true
      end

      it "denies member" do
        expect(UserPolicy.new(member, User.new).create?).to be false
      end
    end

    describe "#edit?" do
      it "allows owner to edit any user" do
        expect(UserPolicy.new(owner, member).edit?).to be true
      end

      it "allows member to edit themselves" do
        expect(UserPolicy.new(member, member).edit?).to be true
      end

      it "denies member from editing others" do
        expect(UserPolicy.new(member, other_member).edit?).to be false
      end
    end

    describe "#update?" do
      it "allows owner to update any user" do
        expect(UserPolicy.new(owner, member).update?).to be true
      end

      it "allows member to update themselves" do
        expect(UserPolicy.new(member, member).update?).to be true
      end

      it "denies member from updating others" do
        expect(UserPolicy.new(member, other_member).update?).to be false
      end
    end

    describe "#destroy?" do
      it "allows owner" do
        expect(UserPolicy.new(owner, member).destroy?).to be true
      end

      it "denies member" do
        expect(UserPolicy.new(member, other_member).destroy?).to be false
      end
    end
  end
end
