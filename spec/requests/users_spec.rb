require 'rails_helper'

RSpec.describe "Users", type: :request do
  # Uses @test_account from spec/support/acts_as_tenant.rb
  let(:account) { @test_account }
  let(:owner) { create(:user, account: account, role: "owner") }
  let(:member) { create(:user, account: account, role: "member") }

  describe "DELETE /users/:id" do
    context "when logged in as owner" do
      before { sign_in owner }

      context "deleting a member" do
        it "deletes the user successfully" do
          expect {
            delete user_path(member)
          }.to change { User.count }.by(-1)

          expect(response).to redirect_to(users_path)
          follow_redirect!
          expect(response.body).to include("User deleted successfully")
        end
      end

      context "trying to delete yourself" do
        it "does not delete and shows error" do
          expect {
            delete user_path(owner)
          }.not_to change { User.count }

          expect(response).to redirect_to(users_path)
          follow_redirect!
          expect(response.body).to include("You cannot delete yourself")
        end
      end

      context "trying to delete the last owner" do
        it "does not delete and shows error" do
          # owner is the only owner
          another_member = create(:user, account: account, role: "member")

          expect {
            delete user_path(owner)
          }.not_to change { User.count }

          expect(response).to redirect_to(users_path)
          follow_redirect!
          expect(response.body).to include("cannot delete yourself")
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
  end
end
