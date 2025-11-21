# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pricing", type: :request do
  let(:account) { create(:account, current_plan: "team") }
  let(:user) { create(:user, account: account) }

  before do
    sign_in user
  end

  describe "GET /pricing" do
    context "with active subscription" do
      let!(:subscription) do
        customer = user.set_payment_processor(:stripe)
        customer.subscribe(
          name: "Team Plan",
          plan: "price_team_monthly",
          quantity: 1
        )
      end

      before do
        # Create some usage data
        ActsAsTenant.with_tenant(account) do
          project = create(:project, account: account)

          # Create events
          create_list(:event, 15, project: project, account: account,
                     occurred_at: Time.current)

          # Create AI summaries
          create_list(:issue, 3, project: project, account: account,
                     ai_summary: "Test", ai_summary_generated_at: Time.current)

          # Create PR tracking
          create_list(:ai_request, 2, account: account, user: user,
                     request_type: "pull_request", occurred_at: Time.current)

          # Create monitors
          create_list(:healthcheck, 2, project: project, account: account, enabled: true)
        end
      end

      it "returns success" do
        get pricing_path
        expect(response).to have_http_status(:success)
      end

      it "assigns account" do
        get pricing_path
        expect(assigns(:account)).to eq(account)
      end

      it "assigns event quota and usage" do
        get pricing_path

        expect(assigns(:event_quota)).to eq(100_000) # Team plan default or account override
        expect(assigns(:events_used)).to eq(15)
        expect(assigns(:events_remaining)).to be > 0
      end

      it "assigns AI summaries quota and usage" do
        get pricing_path

        expect(assigns(:ai_summaries_quota)).to eq(50)
        expect(assigns(:ai_summaries_used)).to eq(3)
        expect(assigns(:ai_summaries_remaining)).to eq(47)
      end

      it "assigns pull requests quota and usage" do
        get pricing_path

        expect(assigns(:pull_requests_quota)).to eq(10)
        expect(assigns(:pull_requests_used)).to eq(2)
        expect(assigns(:pull_requests_remaining)).to eq(8)
      end

      it "assigns uptime monitors quota and usage" do
        get pricing_path

        expect(assigns(:uptime_monitors_quota)).to eq(5)
        expect(assigns(:uptime_monitors_used)).to eq(2)
        expect(assigns(:uptime_monitors_remaining)).to eq(3)
      end

      it "assigns status pages quota and usage" do
        get pricing_path

        expect(assigns(:status_pages_quota)).to eq(1)
        expect(assigns(:status_pages_used)).to eq(0)
        expect(assigns(:status_pages_remaining)).to eq(1)
      end

      it "displays current plan" do
        get pricing_path
        expect(response.body).to include("Current Plan: Team")
      end

      it "displays usage metrics" do
        get pricing_path
        expect(response.body).to include("Error Tracking")
        expect(response.body).to include("AI Summaries")
        expect(response.body).to include("Pull Requests")
      end
    end

    context "without active subscription" do
      it "still displays pricing page" do
        get pricing_path
        expect(response).to have_http_status(:success)
      end

      it "does not show current plan banner" do
        get pricing_path
        expect(response.body).not_to include("Current Plan:")
      end
    end

    context "with different plans" do
      it "displays correct quotas for free plan" do
        account.update!(current_plan: "free")
        get pricing_path

        expect(assigns(:event_quota)).to eq(3_000)
        expect(assigns(:ai_summaries_quota)).to eq(5)
        expect(assigns(:pull_requests_quota)).to eq(5)
      end

      it "displays correct quotas for business plan" do
        account.update!(current_plan: "business")
        get pricing_path

        expect(assigns(:event_quota)).to eq(50_000)
        expect(assigns(:ai_summaries_quota)).to eq(100)
        expect(assigns(:pull_requests_quota)).to eq(20)
      end
    end

    context "when approaching quota limits" do
      before do
        ActsAsTenant.with_tenant(account) do
          project = create(:project, account: account)

          # Create usage near quota (48 out of 50)
          create_list(:issue, 48, project: project, account: account,
                     ai_summary: "Test", ai_summary_generated_at: Time.current)
        end
      end

      it "shows usage near limit" do
        get pricing_path

        expect(assigns(:ai_summaries_used)).to eq(48)
        expect(assigns(:ai_summaries_remaining)).to eq(2)
        expect(response.body).to include("48")
      end
    end

    context "when over quota" do
      before do
        ActsAsTenant.with_tenant(account) do
          project = create(:project, account: account)

          # Create usage over quota (55 out of 50)
          create_list(:issue, 55, project: project, account: account,
                     ai_summary: "Test", ai_summary_generated_at: Time.current)
        end
      end

      it "shows remaining as 0" do
        get pricing_path

        expect(assigns(:ai_summaries_used)).to eq(55)
        expect(assigns(:ai_summaries_remaining)).to eq(0)
      end
    end
  end

  describe "pricing page content" do
    before { get pricing_path }

    it "displays all three pricing tiers" do
      expect(response.body).to include("Free")
      expect(response.body).to include("Team")
      expect(response.body).to include("Business")
    end

    it "displays pricing amounts" do
      expect(response.body).to include("$0")
      expect(response.body).to include("$29")
      expect(response.body).to include("$80")
    end

    it "displays feature comparison table" do
      expect(response.body).to include("Usage Limits")
      expect(response.body).to include("3,000 errors/mo")
      expect(response.body).to include("50K errors/mo")
    end

    it "displays AI summaries limits" do
      expect(response.body).to include("5") # Free plan
      expect(response.body).to include("50") # Team plan
      expect(response.body).to include("100") # Business plan
    end

    it "displays pull request limits" do
      expect(response.body).to include("5") # Free plan
      expect(response.body).to include("10") # Team plan
      expect(response.body).to include("20") # Business plan
    end
  end

  describe "authentication" do
    context "when not signed in" do
      before { sign_out user }

      it "redirects to sign in page" do
        get pricing_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
