class AiProviderConfigsController < ApplicationController
  layout "admin"
  before_action :authenticate_user!
  before_action :set_config, only: [:update, :destroy, :activate]

  def models
    provider = params[:provider].to_s
    unless %w[anthropic openai gemini].include?(provider)
      return render json: { fast: [], power: [] }
    end

    chat_models = RubyLLM.models.by_provider(provider).select { |m| m.type == "chat" }
    sorted = chat_models.sort_by { |m| m.name.downcase }

    render json: {
      fast: sorted.map { |m| { value: m.id, label: m.name } },
      power: sorted.map { |m| { value: m.id, label: m.name } }
    }
  end

  def create
    @config = current_account.ai_provider_configs.build(config_params)

    # Auto-activate if no other configs exist yet
    @config.active = true unless current_account.ai_provider_configs.active.exists?

    if @config.save
      redirect_to account_settings_path, notice: "AI provider added."
    else
      redirect_to account_settings_path, alert: @config.errors.full_messages.join(", ")
    end
  end

  def update
    if @config.update(config_params)
      redirect_to account_settings_path, notice: "AI provider updated."
    else
      redirect_to account_settings_path, alert: @config.errors.full_messages.join(", ")
    end
  end

  def destroy
    @config.destroy
    redirect_to account_settings_path, notice: "AI provider removed."
  end

  def activate
    @config.activate!
    redirect_to account_settings_path, notice: "#{@config.provider.titleize} is now the active AI provider."
  end

  private

  def set_config
    @config = current_account.ai_provider_configs.find(params[:id])
  end

  def config_params
    params.require(:ai_provider_config).permit(:provider, :api_key, :fast_model, :power_model)
  end
end
