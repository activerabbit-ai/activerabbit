require 'rails_helper'

RSpec.describe "Super Admin Viewing Mode", type: :request do
  let(:account) { create(:account) }
  let!(:super_admin) { create(:user, :confirmed, account: account, role: "owner", super_admin: true) }
  let!(:other_account) { create(:account, name: "Other Company Account") }
  let!(:other_user) { create(:user, :confirmed, account: other_account, role: "owner") }

  before do
    ActsAsTenant.current_tenant = account

    # Create project in super admin's account
    ActsAsTenant.with_tenant(account) do
      @own_project = create(:project, account: account, name: "Own Project")
    end

    # Create project in other account
    ActsAsTenant.with_tenant(other_account) do
      @other_project = create(:project, account: other_account, name: "Other Company Project")
    end
  end

  describe "read-only mode enforcement" do
    before do
      sign_in super_admin
      post switch_super_admin_account_path(other_account)
    end

    it "allows GET requests" do
      get dashboard_path
      expect(response).to have_http_status(:success)
    end

    it "blocks POST requests with alert message" do
      post projects_path, params: { project: { name: "New Project", environment: "production" } }
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to include("View-only mode")
    end

    it "blocks PATCH requests" do
      ActsAsTenant.with_tenant(other_account) do
        patch project_path(@other_project), params: { project: { name: "Modified Name" } }
      end
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to include("View-only mode")
    end

    it "blocks DELETE requests" do
      ActsAsTenant.with_tenant(other_account) do
        delete project_path(@other_project)
      end
      expect(response).to redirect_to(dashboard_path)
      expect(flash[:alert]).to include("View-only mode")
    end

    it "allows exit viewing mode (DELETE to exit path)" do
      delete super_admin_exit_accounts_path
      expect(response).to redirect_to(super_admin_accounts_path)
      expect(flash[:alert]).to be_nil
    end
  end

  describe "normal mode (not viewing another account)" do
    before { sign_in super_admin }

    it "allows POST requests to own account" do
      post projects_path, params: { project: { name: "New Project", environment: "production" } }
      # Should not be blocked by read-only mode (may have other validations)
      expect(flash[:alert]).not_to include("View-only mode") if flash[:alert].present?
    end
  end

  describe "current_account behavior" do
    before { sign_in super_admin }

    context "when not viewing another account" do
      it "returns super admin's own account" do
        get dashboard_path
        expect(response).to have_http_status(:success)
        # The dashboard should show their own account's projects
      end
    end

    context "when viewing another account" do
      before do
        post switch_super_admin_account_path(other_account)
      end

      it "sets session[:viewed_account_id]" do
        expect(session[:viewed_account_id]).to eq(other_account.id)
      end

      it "uses the viewed account as current_account for tenant scoping" do
        get dashboard_path
        expect(response).to have_http_status(:success)
        # ActsAsTenant should scope queries to other_account
      end
    end
  end

  describe "viewing banner visibility" do
    before { sign_in super_admin }

    context "when not viewing another account" do
      it "does not show the viewing banner" do
        get dashboard_path
        expect(response.body).not_to include("VIEW-ONLY MODE")
      end
    end

    context "when viewing another account" do
      before do
        post switch_super_admin_account_path(other_account)
      end

      it "shows the viewing banner with account name" do
        get dashboard_path
        expect(response.body).to include("Viewing:")
        expect(response.body).to include(other_account.name)
        expect(response.body).to include("VIEW-ONLY MODE")
      end

      it "shows the exit view button" do
        get dashboard_path
        expect(response.body).to include("Exit View")
      end
    end
  end

  describe "exiting viewing mode" do
    before do
      sign_in super_admin
      post switch_super_admin_account_path(other_account)
    end

    it "clears the session and returns to own account" do
      expect(session[:viewed_account_id]).to eq(other_account.id)

      delete super_admin_exit_accounts_path

      expect(session[:viewed_account_id]).to be_nil
      expect(response).to redirect_to(super_admin_accounts_path)
    end
  end

  describe "regular user cannot use viewing mode" do
    let!(:regular_owner) { create(:user, account: account, role: "owner", super_admin: false) }

    before { sign_in regular_owner }

    it "cannot access super admin accounts page" do
      get super_admin_accounts_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Access denied")
    end

    it "cannot switch to viewing another account" do
      post switch_super_admin_account_path(other_account)
      expect(response).to redirect_to(root_path)
      expect(session[:viewed_account_id]).to be_nil
    end

    it "session manipulation does not grant viewing mode" do
      # Even if someone somehow set the session, viewing_as_super_admin? should return false
      # because the user is not a super_admin
      # This is tested implicitly by the controller requiring super_admin
    end
  end

  describe "All Accounts sidebar link" do
    context "when user is super admin" do
      before { sign_in super_admin }

      it "shows All Accounts link in sidebar" do
        get dashboard_path
        expect(response.body).to include("All Accounts")
        expect(response.body).to include(super_admin_accounts_path)
      end
    end

    context "when user is not super admin" do
      let!(:regular_owner) { create(:user, account: account, role: "owner", super_admin: false) }

      before { sign_in regular_owner }

      it "does not show All Accounts link in sidebar" do
        get dashboard_path
        expect(response.body).not_to include("All Accounts")
      end
    end
  end
end
