require 'rails_helper'

RSpec.describe "SuperAdmin::Accounts", type: :request do
  # Use @test_account from global setup to avoid class reloading issues with Devise
  let(:account) { @test_account }
  let!(:super_admin) { create(:user, account: account, role: "owner", super_admin: true) }
  let!(:regular_owner) { create(:user, account: account, role: "owner", super_admin: false) }
  let!(:other_account) { create(:account, name: "Other Account") }
  let!(:other_user) { create(:user, account: other_account, role: "owner") }

  before do
    # Ensure Devise mappings are loaded for sign_in helper
    Rails.application.reload_routes!
  end

  describe "GET /accounts" do
    context "when logged in as super admin" do
      before { sign_in super_admin }

      it "returns success" do
        get "/accounts"
        expect(response).to have_http_status(:success)
      end

      it "displays all accounts" do
        get "/accounts"
        expect(response.body).to include(account.name)
        expect(response.body).to include(other_account.name)
      end
    end

    context "when logged in as regular owner (not super admin)" do
      before { sign_in regular_owner }

      it "redirects with access denied" do
        get "/accounts"
        expect(response).to redirect_to("/")
        expect(flash[:alert]).to eq("Access denied")
      end
    end

    context "when not logged in" do
      it "redirects to login" do
        get "/accounts"
        expect(response).to redirect_to("/signin")
      end
    end
  end

  describe "GET /accounts/:id" do
    context "when logged in as super admin" do
      before { sign_in super_admin }

      it "returns success" do
        get "/accounts/#{other_account.id}"
        expect(response).to have_http_status(:success)
      end

      it "displays account details" do
        get "/accounts/#{other_account.id}"
        expect(response.body).to include(other_account.name)
      end

      it "displays account users" do
        get "/accounts/#{other_account.id}"
        expect(response.body).to include(other_user.email)
      end
    end

    context "when logged in as regular owner" do
      before { sign_in regular_owner }

      it "redirects with access denied" do
        get "/accounts/#{other_account.id}"
        expect(response).to redirect_to("/")
        expect(flash[:alert]).to eq("Access denied")
      end
    end
  end

  describe "POST /accounts/:id/switch" do
    context "when logged in as super admin" do
      before { sign_in super_admin }

      it "sets viewed_account_id in session" do
        post "/accounts/#{other_account.id}/switch"
        expect(session[:viewed_account_id]).to eq(other_account.id)
      end

      it "redirects to dashboard with notice" do
        post "/accounts/#{other_account.id}/switch"
        expect(response).to redirect_to("/dashboard")
        expect(flash[:notice]).to include(other_account.name)
      end
    end

    context "when logged in as regular owner" do
      before { sign_in regular_owner }

      it "redirects with access denied" do
        post "/accounts/#{other_account.id}/switch"
        expect(response).to redirect_to("/")
        expect(session[:viewed_account_id]).to be_nil
      end
    end
  end

  describe "DELETE /accounts/exit" do
    context "when logged in as super admin viewing another account" do
      before do
        sign_in super_admin
        post "/accounts/#{other_account.id}/switch"
      end

      it "clears viewed_account_id from session" do
        delete "/accounts/exit"
        expect(session[:viewed_account_id]).to be_nil
      end

      it "redirects to accounts index with notice" do
        delete "/accounts/exit"
        expect(response).to redirect_to("/accounts")
        expect(flash[:notice]).to include("Returned to your account")
      end
    end

    context "when logged in as regular owner" do
      before { sign_in regular_owner }

      it "redirects with access denied" do
        delete "/accounts/exit"
        expect(response).to redirect_to("/")
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
      post "/accounts/#{other_account.id}/switch"

      # Verify we can see the other account's dashboard
      get "/dashboard"
      expect(response).to have_http_status(:success)
    end
  end
end
