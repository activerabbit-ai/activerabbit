FactoryBot.define do
  factory :ai_provider_config do
    association :account
    provider { "anthropic" }
    api_key { "sk-ant-test-#{SecureRandom.hex(16)}" }
    fast_model { "claude-haiku-4-5-20251001" }
    power_model { "claude-sonnet-4-6" }
    active { false }
  end
end
