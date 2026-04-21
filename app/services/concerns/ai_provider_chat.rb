module AiProviderChat
  extend ActiveSupport::Concern

  private

  def ai_chat(account, model_type: :fast)
    config = account.ai_provider_config
    return nil unless config

    model = model_type == :power ? config.power_model : config.fast_model

    ctx = RubyLLM.context do |c|
      case config.provider
      when "anthropic"
        c.anthropic_api_key = config.api_key
      when "openai"
        c.openai_api_key = config.api_key
      when "gemini"
        c.gemini_api_key = config.api_key
      end
    end

    ctx.chat(model: model)
  end
end
