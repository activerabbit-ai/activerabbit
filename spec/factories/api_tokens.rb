FactoryBot.define do
  factory :api_token do
    association :account
    association :project
    sequence(:name) { |n| "Token #{n}" }
    token { SecureRandom.hex(32) }
    active { true }
  end
end


