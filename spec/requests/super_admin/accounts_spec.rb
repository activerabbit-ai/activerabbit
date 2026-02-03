require 'rails_helper'

RSpec.describe "SuperAdmin::Accounts", type: :request do
  let(:account) { @test_account }
  let!(:super_admin) { create(:user, account: account, role: "owner", super_admin: true) }
  let!(:regular_owner) { create(:user, account: account, role: "owner", super_admin: false) }
  let!(:other_account) { create(:account, name: "Other Account") }
  let!(:other_user) { create(:user, account: other_account, role: "owner") }

  describe "GET /super_admin/accounts" do
    context "when logged in as super admin" do
      before { sign_in super_admin }

      it "returns success" do
        get super_admin_accounts_path
        expect(response).to have_http_status(:success)
      end

      it "displays all accounts" do
        get super_admin_accounts_path
        expect(response.body).to include(account.name)
        expect(response.body).to include(other_account.name)
      end
    end

    context "when logged in as regular owner (not super admin)" do
      before { sign_in regular_owner }

      it "redirects with access denied" do
        get super_admin_accounts_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Access denied")
      end
    end

    context "when not logged in" do
      it "redirects to login" do
        get super_admin_accounts_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "GET /super_admin/accounts/:id" do
    context "when logged in as super admin" do
      before { sign_in super_admin }

      it "returns success" do
        get super_admin_account_path(other_account)
        expect(response).to have_http_status(:success)
      end

      it "displays account details" do
        get super_admin_account_path(other_account)
        expect(response.body).to include(other_account.name)
      end

      it "displays account users" do
        get super_admin_account_path(other_account)
        expect(response.body).to include(other_user.email)
      end
    end

    context "when logged in as regular owner" do
      before { sign_in regular_owner }

      it "redirects with access denied" do
        get super_admin_account_path(other_account)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Access denied")
      end
    end
  end

  describe "POST /super_admin/accounts/:id/switch" do
    context "when logged in as super admin" do
      before { sign_in super_admin }

      it "sets viewed_account_id in session" do
        post switch_super_admin_account_path(other_account)
        expect(session[:viewed_account_id]).to eq(other_account.id)
      end

      it "redirects to dashboard with notice" do
        post switch_super_admin_account_path(other_account)
        expect(response).to redirect_to(dashboard_path)
        expect(flash[:notice]).to include(other_account.name)
      end
    end

    context "when logged in as regular owner" do
      before { sign_in regular_owner }

      it "redirects with access denied" do
        post switch_super_admin_account_path(other_account)
        expect(response).to redirect_to(root_path)
        expect(session[:viewed_account_id]).to be_nil
      end
    end
  end

  describe "DELETE /super_admin/accounts/exit" do
    context "when logged in as super admin viewing another account" do
      before do
        sign_in super_admin
        post switch_super_admin_account_path(other_account)
      end

      it "clears viewed_account_id from session" do
        delete super_admin_exit_accounts_path
        expect(session[:viewed_account_id]).to be_nil
      end

      it "redirects to accounts index with notice" do
        delete super_admin_exit_accounts_path
        expect(response).to redirect_to(super_admin_accounts_path)
        expect(flash[:notice]).to include("Returned to your account")
      end
    end

    context "when logged in as regular owner" do
      before { sign_in regular_owner }

      it "redirects with access denied" do
        delete super_admin_exit_accounts_path
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "viewing mode integration" do
    before { sign_in super_admin }

    it "allows super admin to view other account's data after switching" do
      # Create a project in the other account
      ActsAsTenant.with_tenant(other_account) do
        create(:project, account: other_account, name: "Other Project")
      end

      # Switch to viewing the other account
      post switch_super_admin_account_path(other_account)

      # Verify we can see the other account's dashboard
      get dashboard_path
      expect(response).to have_http_status(:success)
    end
  end
end
