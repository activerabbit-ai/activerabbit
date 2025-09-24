FactoryBot.define do
  factory :user do
    association :account
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
  end
end


