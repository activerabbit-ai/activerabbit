require 'rails_helper'

RSpec.describe "Users", type: :request do
  # Uses @test_account from spec/support/acts_as_tenant.rb
  let(:account) { @test_account }
  let!(:owner) { create(:user, account: account, role: "owner") }

  describe "DELETE /users/:id" do
    context "when logged in as owner" do
      before { sign_in owner }

      context "deleting a member" do
        let!(:member) { create(:user, account: account, role: "member") }

        it "deletes the user successfully" do
          expect {
            delete user_path(member)
          }.to change { User.count }.by(-1)

          expect(response).to redirect_to(users_path)
        end
      end

      context "trying to delete yourself" do
        it "does not delete and shows error" do
          expect {
            delete user_path(owner)
          }.not_to change { User.count }

          expect(response).to redirect_to(users_path)
          expect(flash[:alert]).to eq("You cannot delete yourself.")
        end
      end

      context "trying to delete the last owner" do
        it "does not delete - triggers self-deletion check first" do
          # Since owner is trying to delete themselves, it triggers
          # the "cannot delete yourself" check before the "last owner" check
          expect {
            delete user_path(owner)
          }.not_to change { User.count }

          expect(response).to redirect_to(users_path)
        end
      end

      context "when there are multiple owners" do
        let!(:another_owner) { create(:user, account: account, role: "owner") }

        it "can delete another owner" do
          expect {
            delete user_path(another_owner)
          }.to change { User.count }.by(-1)

          expect(response).to redirect_to(users_path)
        end
      end
    end

    context "when logged in as member" do
      let!(:member) { create(:user, account: account, role: "member") }

      before { sign_in member }

      it "does not allow deletion" do
        another_member = create(:user, account: account, role: "member")

        expect {
          delete user_path(another_member)
        }.not_to change { User.count }

        # Should redirect due to require_owner! check
        expect(response).to redirect_to(root_path)
      end
    end

    context "when not logged in" do
      let!(:member) { create(:user, account: account, role: "member") }

      it "redirects to login" do
        delete user_path(member)
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "POST /users (invite)" do
    before { sign_in owner }

    it "creates a new user with member role" do
      expect {
        post users_path, params: {
          user: { email: "newuser@example.com", role: "member" }
        }
      }.to change { User.count }.by(1)

      new_user = User.last
      expect(new_user.email).to eq("newuser@example.com")
      expect(new_user.role).to eq("member")
      expect(new_user.invited_by).to eq(owner)
    end

    it "queues a welcome email job" do
      expect {
        post users_path, params: {
          user: { email: "newuser@example.com", role: "member" }
        }
      }.to change { SendWelcomeEmailJob.jobs.size }.by(1)
    end

    it "generates a reset password token" do
      post users_path, params: {
        user: { email: "newuser@example.com", role: "member" }
      }

      new_user = User.last
      expect(new_user.reset_password_token).to be_present
      expect(new_user.reset_password_sent_at).to be_present
    end

    context "regular owner cannot set super_admin" do
      it "ignores super_admin param when owner is not super_admin" do
        post users_path, params: {
          user: { email: "newuser@example.com", role: "member", super_admin: "1" }
        }

        new_user = User.last
        expect(new_user.super_admin).to be false
      end
    end
  end

  describe "super admin user management" do
    let!(:super_admin) { create(:user, account: account, role: "owner", super_admin: true) }

    describe "POST /users (invite as super admin)" do
      before { sign_in super_admin }

      it "allows super admin to create another super admin" do
        post users_path, params: {
          user: { email: "newsuperadmin@example.com", role: "owner", super_admin: "1" }
        }

        new_user = User.find_by(email: "newsuperadmin@example.com")
        expect(new_user.super_admin).to be true
      end

      it "creates regular user when super_admin is not set" do
        post users_path, params: {
          user: { email: "regularuser@example.com", role: "member" }
        }

        new_user = User.find_by(email: "regularuser@example.com")
        expect(new_user.super_admin).to be false
      end
    end

    describe "PATCH /users/:id (update as super admin)" do
      let!(:regular_user) { create(:user, account: account, role: "member", super_admin: false) }

      before { sign_in super_admin }

      it "allows super admin to grant super admin to another user" do
        patch user_path(regular_user), params: {
          user: { super_admin: "1" }
        }

        expect(regular_user.reload.super_admin).to be true
      end

      it "allows super admin to revoke super admin from another user" do
        regular_user.update!(super_admin: true)

        patch user_path(regular_user), params: {
          user: { super_admin: "0" }
        }

        expect(regular_user.reload.super_admin).to be false
      end

      it "does not allow super admin to modify their own super admin status" do
        # Super admin cannot modify themselves via this route
        # (the form doesn't show the checkbox for editing yourself)
        patch user_path(super_admin), params: {
          user: { email: super_admin.email, super_admin: "0" }
        }

        # super_admin status should remain unchanged
        expect(super_admin.reload.super_admin).to be true
      end
    end

    describe "PATCH /users/:id (update as regular owner)" do
      let!(:regular_user) { create(:user, account: account, role: "member", super_admin: false) }

      before { sign_in owner }

      it "does not allow regular owner to grant super admin" do
        patch user_path(regular_user), params: {
          user: { super_admin: "1" }
        }

        expect(regular_user.reload.super_admin).to be false
      end
    end
  end
end
