FactoryBot.define do
  factory :release do
    association :account
    association :project
    sequence(:version) { |n| "v1.0.#{n}" }
    environment { 'production' }
    deployed_at { Time.current }
    metadata { {} }
  end
end

