FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Account #{n}" }
    active { true }
  end
end
