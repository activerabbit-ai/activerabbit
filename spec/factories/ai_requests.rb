FactoryBot.define do
  factory :ai_request do
    association :account
    association :user
    request_type { "pull_request" }
    occurred_at { Time.current }
  end
end


