FactoryBot.define do
  factory :healthcheck do
    association :project
    association :account
    sequence(:name) { |n| "Homepage #{n}" }
    check_type { "http" }
    status { "healthy" }
    enabled { true }
    last_checked_at { Time.current }
    response_time_ms { 10.5 }
    message { "OK" }
    config { { "url" => "https://example.com", "timeout" => 5 } }
  end
end


