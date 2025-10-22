FactoryBot.define do
  factory :project do
    association :account
    association :user
    sequence(:name) { |n| "Project #{n}" }
    sequence(:slug) { |n| "project-#{n}" }
    url { "http://example.com" }
    environment { "production" }
    active { true }
    settings { {} }
  end
end



