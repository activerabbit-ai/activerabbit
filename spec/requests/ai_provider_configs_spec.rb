require 'rails_helper'

RSpec.describe "AiProviderConfigs", type: :request do
  let(:account) { create(:account, :team_plan) }
  let(:user) { create(:user, :confirmed, :owner, account: account) }

  before do
    ActsAsTenant.current_tenant = account
    login_as user, scope: :user
  end

  describe "POST /account/settings/ai_provider_configs" do
    let(:valid_params) do
      {
        ai_provider_config: {
          provider: "anthropic",
          api_key: "sk-ant-test-key",
          fast_model: "claude-haiku-4-5-20251001",
          power_model: "claude-sonnet-4-6"
        }
      }
    end

    it "creates a new provider config" do
      expect {
        post account_settings_ai_provider_configs_path, params: valid_params
      }.to change(AiProviderConfig, :count).by(1)
    end

    it "redirects to account settings with notice" do
      post account_settings_ai_provider_configs_path, params: valid_params
      expect(response).to redirect_to(account_settings_path)
    end

    it "auto-activates the first config" do
      post account_settings_ai_provider_configs_path, params: valid_params
      expect(account.ai_provider_configs.last).to be_active
    end
  end

  describe "PATCH /account/settings/ai_provider_configs/:id" do
    let!(:config) { create(:ai_provider_config, account: account, active: true) }

    it "updates the provider config" do
      patch account_settings_ai_provider_config_path(config), params: {
        ai_provider_config: { fast_model: "gpt-4o-mini" }
      }
      expect(config.reload.fast_model).to eq("gpt-4o-mini")
    end
  end

  describe "DELETE /account/settings/ai_provider_configs/:id" do
    let!(:config) { create(:ai_provider_config, account: account) }

    it "destroys the provider config" do
      expect {
        delete account_settings_ai_provider_config_path(config)
      }.to change(AiProviderConfig, :count).by(-1)
    end
  end

  describe "POST /account/settings/ai_provider_configs/:id/activate" do
    let!(:config_a) { create(:ai_provider_config, account: account, active: true) }
    let!(:config_b) { create(:ai_provider_config, account: account, provider: "openai", active: false) }

    it "activates the specified config and deactivates others" do
      post activate_account_settings_ai_provider_config_path(config_b)

      expect(config_b.reload).to be_active
      expect(config_a.reload).not_to be_active
    end

    it "redirects to account settings" do
      post activate_account_settings_ai_provider_config_path(config_b)
      expect(response).to redirect_to(account_settings_path)
    end
  end
end
