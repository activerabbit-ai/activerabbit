FactoryBot.define do
  factory :user do
    association :account
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }

    trait :super_admin do
      super_admin { true }
    end

    trait :owner do
      role { "owner" }
    end

    trait :member do
      role { "member" }
    end
  end
end
